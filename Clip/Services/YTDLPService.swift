import Foundation
import os

private let ytdlpLogger = Logger(subsystem: "com.clip.app", category: "yt-dlp")

actor YTDLPService {
    private let binaryPath: String

    /// Directory containing bundled ffmpeg/ffprobe binaries
    static let bundledResourceDir: String? = {
        // Prefer direct resource URL (reliable for extensionless binaries)
        if let resourceURL = Bundle.main.resourceURL {
            let ffmpegURL = resourceURL.appendingPathComponent("ffmpeg")
            if FileManager.default.fileExists(atPath: ffmpegURL.path) {
                return resourceURL.path
            }
        }
        // Fallback: path(forResource:) lookup
        if let ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return (ffmpegPath as NSString).deletingLastPathComponent
        }
        return nil
    }()

    static let enrichedEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        var extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/homebrew/sbin"]
        // Include bundled Resources dir so yt-dlp can find ffmpeg in PATH too
        if let resourceDir = bundledResourceDir {
            extraPaths.insert(resourceDir, at: 0)
        }
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let newPaths = extraPaths.filter { !currentPath.contains($0) }
        if !newPaths.isEmpty {
            env["PATH"] = (newPaths + [currentPath]).joined(separator: ":")
        }
        return env
    }()

    init() {
        if let bundledPath = Bundle.main.path(forResource: "yt-dlp", ofType: nil) {
            self.binaryPath = bundledPath
        } else {
            // Fallback: look in PATH
            let whichProcess = Process()
            let pipe = Pipe()
            whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichProcess.arguments = ["yt-dlp"]
            whichProcess.standardOutput = pipe
            whichProcess.standardError = FileHandle.nullDevice
            try? whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.binaryPath = path.isEmpty ? "/opt/homebrew/bin/yt-dlp" : path
        }
    }

    func ensureExecutable() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: binaryPath) else {
            throw YTDLPError.binaryNotFound(binaryPath)
        }
        if !fm.isExecutableFile(atPath: binaryPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = ["+x", binaryPath]
            try process.run()
            process.waitUntilExit()
        }
    }

    func fetchMetadata(url: String) async throws -> VideoMetadata {
        ytdlpLogger.info("Fetching metadata for \(url, privacy: .public)")
        try ensureExecutable()

        // Try with cookies first, then without on failure
        let cookieArgs = Self.cookieArgs(for: url)
        if let cookieArgs = cookieArgs {
            if let result = try? await runMetadataFetch(url: url, extraArgs: cookieArgs) {
                return result
            }
        }
        // Fallback: no cookies
        return try await runMetadataFetch(url: url, extraArgs: [])
    }

    private func runMetadataFetch(url: String, extraArgs: [String]) async throws -> VideoMetadata {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.environment = Self.enrichedEnvironment
        var args = ["--dump-json", "--no-download"] + extraArgs
        args.append(url)
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        // If we got valid JSON stdout, use it even if exit code is non-zero
        // (yt-dlp sometimes exits non-zero with cookie warnings but still outputs data)
        if !stdoutData.isEmpty {
            let decoder = JSONDecoder()
            if let metadata = try? decoder.decode(VideoMetadata.self, from: stdoutData) {
                return metadata
            }
        }

        guard process.terminationStatus == 0 else {
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            let errorLines = stderrString
                .components(separatedBy: .newlines)
                .filter { $0.contains("ERROR") }
            let errorMessage = errorLines.isEmpty ? stderrString : errorLines.joined(separator: "\n")
            ytdlpLogger.error("yt-dlp fetch failed: \(errorMessage, privacy: .public)")
            throw YTDLPError.fetchFailed(errorMessage)
        }

        ytdlpLogger.error("yt-dlp returned no data for \(url, privacy: .public)")
        throw YTDLPError.noData
    }

    nonisolated func startDownload(
        url: String,
        formatId: String?,
        outputFormat: OutputFormat,
        resolution: OutputResolution,
        clipRange: ClipRange? = nil,
        outputDirectory: String,
        onProgress: @escaping @Sendable (Double, String, String) -> Void,
        onComplete: @escaping @Sendable (String?, String?) -> Void
    ) throws -> Process {
        let fm = FileManager.default
        guard fm.fileExists(atPath: binaryPath) else {
            throw YTDLPError.binaryNotFound(binaryPath)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.environment = Self.enrichedEnvironment

        var args: [String] = []

        // Point yt-dlp to bundled ffmpeg so --force-keyframes-at-cuts and merging work
        if let resourceDir = Self.bundledResourceDir {
            args += ["--ffmpeg-location", resourceDir]
            ytdlpLogger.info("Using bundled ffmpeg at \(resourceDir)")
        } else {
            ytdlpLogger.warning("Bundled ffmpeg not found — clip downloads may fail")
        }

        if let cookieArgs = Self.cookieArgs(for: url) {
            args += cookieArgs
        }

        // Format selection
        if outputFormat.isAudioOnly {
            args += ["-x", "--audio-format", "mp3"]
            if let fid = formatId {
                args += ["-f", fid]
            } else {
                args += ["-f", "bestaudio"]
            }
        } else {
            if let fid = formatId {
                args += ["-f", "\(fid)+bestaudio/\(fid)/best"]
            } else {
                args += ["-f", "bestvideo[height<=\(resolution.rawValue)]+bestaudio/best[height<=\(resolution.rawValue)]/best"]
            }

            if outputFormat == .mov {
                args += ["--recode-video", "mov"]
            } else if outputFormat == .mp4 {
                args += ["--merge-output-format", "mp4"]
            } else if outputFormat == .webm {
                args += ["--merge-output-format", "webm"]
            }
        }

        // Clip range: use --download-sections + --force-keyframes-at-cuts for precise trimming
        if let clip = clipRange {
            let startTime = ClipRange.formatTimePrecise(clip.start)
            let endTime = ClipRange.formatTimePrecise(clip.end)
            args += ["--download-sections", "*\(startTime)-\(endTime)"]
            args += ["--force-keyframes-at-cuts"]
        }

        let clipSuffix: String
        if let clip = clipRange {
            let startTag = ClipRange.formatTime(clip.start).replacingOccurrences(of: ":", with: ".")
            let endTag = ClipRange.formatTime(clip.end).replacingOccurrences(of: ":", with: ".")
            clipSuffix = "_clip_\(startTag)-\(endTag)"
        } else {
            clipSuffix = ""
        }
        let outputTemplate = "\(outputDirectory)/%(title).100s_\(resolution.rawValue)p\(clipSuffix).%(ext)s"
        args += ["-o", outputTemplate]
        args += ["--newline", "--progress"]
        args += ["--no-overwrites"]
        args.append(url)

        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let pathHolder = OutputPathHolder()

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

            for singleLine in line.components(separatedBy: .newlines) {
                let trimmed = singleLine.trimmingCharacters(in: .whitespaces)

                // Parse progress: [download]  45.2% of ~123.45MiB at 5.23MiB/s ETA 00:15
                if trimmed.hasPrefix("[download]") && trimmed.contains("%") {
                    let progressInfo = Self.parseProgress(trimmed)
                    onProgress(progressInfo.percent, progressInfo.speed, progressInfo.eta)
                }

                // Parse destination: [download] Destination: /path/to/file.mp4
                if trimmed.contains("Destination:") {
                    let parts = trimmed.components(separatedBy: "Destination:")
                    if parts.count > 1 {
                        pathHolder.path = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }

                // Parse already downloaded: [download] /path/to/file.mp4 has already been downloaded
                if trimmed.hasPrefix("[download]") && trimmed.contains("has already been downloaded") {
                    let path = trimmed
                        .replacingOccurrences(of: "[download] ", with: "")
                        .replacingOccurrences(of: " has already been downloaded", with: "")
                    if !path.isEmpty {
                        pathHolder.path = path
                    }
                }

                // Merger output
                if trimmed.hasPrefix("[Merger]") || trimmed.hasPrefix("[ExtractAudio]") {
                    if let range = trimmed.range(of: "Merging formats into \"") {
                        let start = range.upperBound
                        if let end = trimmed.range(of: "\"", range: start..<trimmed.endIndex) {
                            pathHolder.path = String(trimmed[start..<end.lowerBound])
                        }
                    }
                }
            }
        }

        let stderrHandle = stderrPipe.fileHandleForReading
        let errorHolder = OutputPathHolder()

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            for singleLine in line.components(separatedBy: .newlines) {
                let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("ERROR") {
                    errorHolder.path = trimmed
                }
                // yt-dlp may output Destination to stderr
                if trimmed.contains("Destination:") {
                    let parts = trimmed.components(separatedBy: "Destination:")
                    if parts.count > 1 {
                        pathHolder.path = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        let outputDir = outputDirectory
        process.terminationHandler = { proc in
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            if proc.terminationStatus == 0 {
                // If we captured the path, use it; otherwise find the newest file in output dir
                let finalPath = pathHolder.path ?? Self.newestFile(in: outputDir)
                onComplete(finalPath, nil)
            } else {
                Self.cleanupPartialFiles(in: outputDir, pathHint: pathHolder.path)
                onComplete(nil, errorHolder.path ?? "Download failed (exit code \(proc.terminationStatus))")
            }
        }

        try process.run()
        return process
    }

    private static func cleanupPartialFiles(in directory: String, pathHint: String?) {
        guard let hint = pathHint else { return }
        let fm = FileManager.default
        let baseName = (hint as NSString).deletingPathExtension
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for file in files {
            let fullPath = "\(directory)/\(file)"
            if fullPath.hasPrefix(baseName) && (file.hasSuffix(".part") || file.contains(".ytdl")) {
                try? fm.removeItem(atPath: fullPath)
            }
        }
    }

    private static func newestFile(in directory: String) -> String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return nil }
        let now = Date()
        return files
            .map { "\(directory)/\($0)" }
            .compactMap { path -> (String, Date)? in
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modified = attrs[.modificationDate] as? Date,
                      now.timeIntervalSince(modified) < ClipConstants.fileRecencySeconds
                else { return nil }
                return (path, modified)
            }
            .max(by: { $0.1 < $1.1 })?.0
    }

    private static func cookieArgs(for url: String) -> [String]? {
        // Only Instagram truly requires auth cookies; YouTube and X.com work without
        guard url.contains("instagram.com") else { return nil }

        let fm = FileManager.default
        let home = NSHomeDirectory()

        // Arc is Chromium-based but not natively supported by yt-dlp.
        // Use chrome reader with Arc's data path.
        let arcDataPath = "\(home)/Library/Application Support/Arc/User Data"
        if fm.fileExists(atPath: "/Applications/Arc.app") && fm.fileExists(atPath: arcDataPath) {
            return ["--cookies-from-browser", "chrome:\(arcDataPath)"]
        }

        let browsers: [(name: String, path: String)] = [
            ("chrome", "/Applications/Google Chrome.app"),
            ("safari", "/Applications/Safari.app"),
            ("firefox", "/Applications/Firefox.app"),
            ("brave", "/Applications/Brave Browser.app"),
            ("edge", "/Applications/Microsoft Edge.app"),
            ("opera", "/Applications/Opera.app"),
        ]

        for browser in browsers {
            if fm.fileExists(atPath: browser.path) {
                return ["--cookies-from-browser", browser.name]
            }
        }
        return nil
    }

    private static func parseProgress(_ line: String) -> (percent: Double, speed: String, eta: String) {
        var percent: Double = 0
        var speed = ""
        var eta = ""

        // Extract percentage
        if let percentRange = line.range(of: #"[\d.]+%"#, options: .regularExpression) {
            let percentStr = line[percentRange].dropLast() // Remove %
            percent = Double(percentStr) ?? 0
        }

        // Extract speed
        if let speedRange = line.range(of: #"at\s+[\d.]+\S+"#, options: .regularExpression) {
            speed = String(line[speedRange]).replacingOccurrences(of: "at ", with: "")
        }

        // Extract ETA
        if let etaRange = line.range(of: #"ETA\s+[\d:]+|ETA\s+Unknown"#, options: .regularExpression) {
            eta = String(line[etaRange]).replacingOccurrences(of: "ETA ", with: "")
        }

        return (percent, speed, eta)
    }
}

private final class OutputPathHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _path: String?

    var path: String? {
        get { lock.withLock { _path } }
        set { lock.withLock { _path = newValue } }
    }
}

extension YTDLPService {
    static func friendlyError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("is not a valid url") || lower.contains("unsupported url") {
            return "This URL isn't supported. Try a direct video link."
        }
        if lower.contains("private video") || lower.contains("login required") {
            return "This video is private or requires login."
        }
        if lower.contains("video unavailable") || lower.contains("not available") {
            return "This video is unavailable or has been removed."
        }
        if lower.contains("geo") || lower.contains("not available in your country") {
            return "This video is geo-restricted in your region."
        }
        if lower.contains("age") || lower.contains("sign in to confirm your age") {
            return "This video is age-restricted and requires login."
        }
        if lower.contains("copyright") {
            return "This video was removed due to a copyright claim."
        }
        if lower.contains("429") || lower.contains("too many requests") || lower.contains("rate limit") {
            return "Too many requests. Wait a moment and try again."
        }
        if lower.contains("unable to extract") || lower.contains("no video formats") {
            return "Couldn't extract video. The link may be invalid or expired."
        }
        if lower.contains("urlopen error") || lower.contains("connection") || lower.contains("timed out") {
            return "Network error. Check your internet connection."
        }
        // Truncate long messages
        if message.count > 120 {
            return String(message.prefix(120)) + "..."
        }
        return message
    }
}

enum YTDLPError: LocalizedError {
    case binaryNotFound(String)
    case fetchFailed(String)
    case noData
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "yt-dlp not found at \(path). Install it via Homebrew: brew install yt-dlp"
        case .fetchFailed(let msg):
            return "Failed to fetch video info: \(msg)"
        case .noData:
            return "No data received from yt-dlp"
        case .parseFailed(let msg):
            return "Failed to parse video info: \(msg)"
        }
    }
}
