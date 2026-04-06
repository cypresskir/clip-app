import Foundation
import os

private let ffmpegLogger = Logger(subsystem: "com.clip.app", category: "ffmpeg")

struct FFmpegService {
    private static func findBinary() -> String? {
        // Check bundled binary first
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }

        // Fallback: check common paths
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try which
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        process.environment = YTDLPService.enrichedEnvironment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    static var isAvailable: Bool {
        findBinary() != nil
    }

    /// Two-pass compress a video to fit within targetBytes.
    /// Calls onProgress with 0.0–1.0 during encoding.
    /// Returns the path to the compressed file.
    static func compress(
        inputPath: String,
        targetBytes: Int64,
        audioBitrateKbps: Int = 128,
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<String, Error>) -> Void
    ) -> Process? {
        guard let ffmpegPath = findBinary() else {
            onComplete(.failure(CompressionError.ffmpegNotFound))
            return nil
        }

        // Get duration first — guard against zero/near-zero to prevent division issues
        guard let duration = probeDuration(inputPath: inputPath, ffmpegPath: ffmpegPath),
              duration > 0.1 else {
            onComplete(.failure(CompressionError.noDuration))
            return nil
        }

        // Calculate target video bitrate
        // targetBytes * 8 = total bits; subtract audio bits; divide by duration
        let totalBits = Double(targetBytes) * 8.0
        let audioBits = Double(audioBitrateKbps) * 1000.0 * duration
        let videoBits = max(totalBits - audioBits, 100_000) // min 100kbps
        let videoBitrateKbps = Int(videoBits / duration / 1000.0)

        let ext = (inputPath as NSString).pathExtension.lowercased()
        let baseName = (inputPath as NSString).deletingPathExtension
        let outputPath = "\(baseName)_compressed.\(ext)"
        let passLogFile = NSTemporaryDirectory() + "clip_ffmpeg_\(UUID().uuidString)"

        ffmpegLogger.info("Compressing \(inputPath, privacy: .public) to target \(targetBytes) bytes (video: \(videoBitrateKbps)kbps)")

        // Run pass 1 then pass 2 sequentially
        let pass1Args = buildArgs(
            pass: 1, videoBitrateKbps: videoBitrateKbps,
            audioBitrateKbps: audioBitrateKbps,
            inputPath: inputPath, outputPath: "/dev/null",
            passLogFile: passLogFile, ext: ext
        )
        let pass2Args = buildArgs(
            pass: 2, videoBitrateKbps: videoBitrateKbps,
            audioBitrateKbps: audioBitrateKbps,
            inputPath: inputPath, outputPath: outputPath,
            passLogFile: passLogFile, ext: ext
        )

        // Run pass 1 in background, then pass 2
        let totalDuration = duration
        runPass(
            ffmpegPath: ffmpegPath, args: pass1Args,
            duration: totalDuration, progressOffset: 0, progressScale: 0.5,
            onProgress: onProgress
        ) { result in
            switch result {
            case .failure(let error):
                cleanupPassLogs(passLogFile)
                onComplete(.failure(error))
            case .success:
                // Run pass 2
                let process = runPass(
                    ffmpegPath: ffmpegPath, args: pass2Args,
                    duration: totalDuration, progressOffset: 0.5, progressScale: 0.5,
                    onProgress: onProgress
                ) { result in
                    cleanupPassLogs(passLogFile)
                    switch result {
                    case .failure(let error):
                        onComplete(.failure(error))
                    case .success:
                        // Atomically replace original with compressed
                        let fm = FileManager.default
                        let inputURL = URL(fileURLWithPath: inputPath)
                        let outputURL = URL(fileURLWithPath: outputPath)
                        // Verify compressed file exists and is non-empty
                        if let attrs = try? fm.attributesOfItem(atPath: outputPath),
                           let size = attrs[.size] as? Int64, size > 0 {
                            do {
                                _ = try fm.replaceItemAt(inputURL, withItemAt: outputURL)
                                onComplete(.success(inputPath))
                            } catch {
                                // Atomic replace failed — return whichever file exists
                                onComplete(.success(fm.fileExists(atPath: outputPath) ? outputPath : inputPath))
                            }
                        } else {
                            // Compressed file missing or empty — keep original
                            try? fm.removeItem(atPath: outputPath)
                            onComplete(.success(inputPath))
                        }
                    }
                }
                _ = process // keep reference alive through closure
            }
        }

        return nil // pass1 process is internal
    }

    private static func buildArgs(
        pass: Int, videoBitrateKbps: Int, audioBitrateKbps: Int,
        inputPath: String, outputPath: String,
        passLogFile: String, ext: String
    ) -> [String] {
        var args = ["-y", "-i", inputPath]

        // Use H.264 for broad compatibility
        args += ["-c:v", "libx264", "-b:v", "\(videoBitrateKbps)k"]
        args += ["-preset", "medium"]
        args += ["-pass", "\(pass)", "-passlogfile", passLogFile]

        if pass == 1 {
            args += ["-an", "-f", ext == "webm" ? "webm" : "mp4"]
        } else {
            args += ["-c:a", "aac", "-b:a", "\(audioBitrateKbps)k"]
        }

        args += ["-progress", "pipe:1"]
        args.append(outputPath)
        return args
    }

    @discardableResult
    private static func runPass(
        ffmpegPath: String, args: [String],
        duration: Double, progressOffset: Double, progressScale: Double,
        onProgress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) -> Process {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.environment = YTDLPService.enrichedEnvironment
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let totalDuration = duration
        let offset = progressOffset
        let scale = progressScale

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            // Parse "out_time_us=12345678" from ffmpeg progress
            for line in output.components(separatedBy: .newlines) {
                if line.hasPrefix("out_time_us=") {
                    let usStr = line.replacingOccurrences(of: "out_time_us=", with: "")
                    if let us = Double(usStr), totalDuration > 0 {
                        let seconds = us / 1_000_000.0
                        let passProgress = min(seconds / totalDuration, 1.0)
                        onProgress(offset + passProgress * scale)
                    }
                }
            }
        }

        // Suppress stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            if proc.terminationStatus == 0 {
                completion(.success(()))
            } else {
                completion(.failure(CompressionError.encodingFailed(Int(proc.terminationStatus))))
            }
        }

        try? process.run()
        return process
    }

    private static func probeDuration(inputPath: String, ffmpegPath: String) -> Double? {
        // Check bundled ffprobe first, then same directory as ffmpeg
        let fm = FileManager.default
        let ffprobePath: String
        if let bundled = Bundle.main.path(forResource: "ffprobe", ofType: nil),
           fm.isExecutableFile(atPath: bundled) {
            ffprobePath = bundled
        } else {
            let siblingPath = (ffmpegPath as NSString).deletingLastPathComponent + "/ffprobe"
            guard fm.isExecutableFile(atPath: siblingPath) else { return nil }
            ffprobePath = siblingPath
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "quiet", "-print_format", "json",
            "-show_format", inputPath
        ]
        process.environment = YTDLPService.enrichedEnvironment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let format = json["format"] as? [String: Any],
           let durationStr = format["duration"] as? String,
           let duration = Double(durationStr) {
            return duration
        }
        return nil
    }

    private static func cleanupPassLogs(_ prefix: String) {
        let fm = FileManager.default
        let dir = (prefix as NSString).deletingLastPathComponent
        if let files = try? fm.contentsOfDirectory(atPath: dir) {
            let base = (prefix as NSString).lastPathComponent
            for file in files where file.hasPrefix(base) {
                try? fm.removeItem(atPath: "\(dir)/\(file)")
            }
        }
    }
}

enum CompressionError: LocalizedError {
    case ffmpegNotFound
    case noDuration
    case encodingFailed(Int)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Install it via Homebrew: brew install ffmpeg"
        case .noDuration:
            return "Could not determine video duration for compression."
        case .encodingFailed(let code):
            return "Compression failed (ffmpeg exit code \(code))"
        }
    }
}
