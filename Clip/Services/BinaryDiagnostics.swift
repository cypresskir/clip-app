import Foundation

struct DiagEntry: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let ok: Bool
}

@MainActor
class BinaryDiagnosticsModel: ObservableObject {
    @Published var entries: [DiagEntry] = [DiagEntry(label: "Status", value: "Running checks...", ok: true)]

    func runChecks() {
        Task.detached {
            let results = BinaryDiagnostics.run()
            await MainActor.run {
                self.entries = results
            }
        }
    }
}

enum BinaryDiagnostics {
    static func run() -> [DiagEntry] {
        var entries: [DiagEntry] = []
        let fm = FileManager.default

        let bundlePath = Bundle.main.bundlePath
        let resourceDir = bundlePath + "/Contents/Resources"

        entries.append(DiagEntry(
            label: "Bundle path",
            value: bundlePath,
            ok: true
        ))

        entries.append(DiagEntry(
            label: "Resources dir exists",
            value: fm.fileExists(atPath: resourceDir) ? "Yes" : "No",
            ok: fm.fileExists(atPath: resourceDir)
        ))

        for bin in ["yt-dlp", "ffmpeg", "ffprobe"] {
            let path = resourceDir + "/" + bin

            let exists = fm.fileExists(atPath: path)
            entries.append(DiagEntry(
                label: "\(bin) exists",
                value: exists ? "Yes" : "MISSING",
                ok: exists
            ))

            if exists {
                let executable = fm.isExecutableFile(atPath: path)
                entries.append(DiagEntry(
                    label: "\(bin) executable",
                    value: executable ? "Yes" : "No (+x missing)",
                    ok: executable
                ))

                let (runs, detail) = testBinary(path: path, arg: bin == "yt-dlp" ? "--version" : "-version")
                entries.append(DiagEntry(
                    label: "\(bin) runs",
                    value: runs ? detail : "FAILED: \(detail)",
                    ok: runs
                ))
            }
        }

        // Check what yt-dlp sees for ffmpeg
        let ytdlpPath = resourceDir + "/yt-dlp"
        if fm.isExecutableFile(atPath: ytdlpPath) {
            let (_, verboseOutput) = testBinary(
                path: ytdlpPath,
                args: ["--ffmpeg-location", resourceDir, "--verbose", "--version"],
                env: YTDLPService.enrichedEnvironment
            )
            if let range = verboseOutput.range(of: "ffmpeg") {
                let context = String(verboseOutput[range.lowerBound...].prefix(80))
                entries.append(DiagEntry(label: "yt-dlp sees ffmpeg", value: context, ok: true))
            } else {
                entries.append(DiagEntry(label: "yt-dlp sees ffmpeg", value: "NOT DETECTED", ok: false))
            }
        }

        return entries
    }

    private static func testBinary(path: String, arg: String) -> (Bool, String) {
        testBinary(path: path, args: [arg], env: nil)
    }

    private static func testBinary(path: String, args: [String], env: [String: String]?) -> (Bool, String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = stdout
        process.standardError = stderr
        if let env { process.environment = env }

        do {
            try process.run()
            process.waitUntilExit()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = (String(data: outData, encoding: .utf8) ?? "") +
                         (String(data: errData, encoding: .utf8) ?? "")
            let firstLine = output.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? output
            if process.terminationStatus == 0 {
                return (true, String(firstLine.prefix(80)))
            } else {
                return (false, "exit \(process.terminationStatus): \(String(firstLine.prefix(60)))")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
