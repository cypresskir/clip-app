import Foundation
import AppKit
import os

private let updateLogger = Logger(subsystem: "com.clip.app", category: "updates")

/// Lightweight self-update system using GitHub Releases as the distribution server.
/// Checks for new versions, downloads the .zip, extracts, and replaces the running app.
@MainActor
class UpdateService: ObservableObject {
    /// Set this to your GitHub repo in "owner/repo" format.
    static let githubRepo = "cypresskir/clip-app"

    /// Current app version from Info.plist
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    @Published var updateAvailable: Release?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    struct Release: Codable {
        let tagName: String
        let name: String?
        let body: String?
        let assets: [Asset]
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, assets
            case htmlUrl = "html_url"
        }

        struct Asset: Codable {
            let name: String
            let browserDownloadUrl: String
            let size: Int

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
                case size
            }
        }

        /// Semver string from tag (strips leading "v")
        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
    }

    /// Check GitHub for a newer release.
    func checkForUpdate() async {
        isChecking = true
        error = nil
        defer { isChecking = false }

        let urlString = "https://api.github.com/repos/\(Self.githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 404 {
                // No releases yet
                updateLogger.info("No releases found on GitHub")
                return
            }

            guard httpResponse.statusCode == 200 else {
                updateLogger.warning("GitHub API returned \(httpResponse.statusCode)")
                return
            }

            let release = try JSONDecoder().decode(Release.self, from: data)

            if isNewer(release.version, than: Self.currentVersion) {
                updateLogger.info("Update available: \(release.version) (current: \(Self.currentVersion))")
                updateAvailable = release
            } else {
                updateLogger.info("App is up to date (\(Self.currentVersion))")
                updateAvailable = nil
            }
        } catch {
            updateLogger.error("Update check failed: \(error.localizedDescription)")
            // Silently fail — don't bother the user if the check fails
        }
    }

    /// Download and install the update, replacing the current app bundle.
    func downloadAndInstall() async {
        guard let release = updateAvailable else { return }

        // Find the .zip asset (e.g., "Clip.zip" or "Clip-v1.1.0.zip")
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            error = "No .zip asset found in release"
            return
        }

        guard let downloadURL = URL(string: asset.browserDownloadUrl) else { return }

        isDownloading = true
        downloadProgress = 0
        error = nil

        do {
            // Download to temp
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipUpdate_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent(asset.name)

            updateLogger.info("Downloading update from \(asset.browserDownloadUrl)")

            // Download with progress
            let (localURL, _) = try await downloadWithProgress(from: downloadURL, expectedSize: asset.size)

            try FileManager.default.moveItem(at: localURL, to: zipPath)

            updateLogger.info("Download complete, extracting...")
            downloadProgress = 0.9

            // Unzip
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzipProcess.arguments = ["-xk", zipPath.path, tempDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                throw UpdateError.extractionFailed
            }

            // Find the .app in extracted contents
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.noAppFound
            }

            // Remove quarantine
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", newApp.path]
            try xattrProcess.run()
            xattrProcess.waitUntilExit()

            // Replace the current app
            let currentAppPath = Bundle.main.bundlePath
            let backupPath = currentAppPath + ".backup"

            // Backup current app
            if FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.removeItem(atPath: backupPath)
            }
            try FileManager.default.moveItem(atPath: currentAppPath, toPath: backupPath)

            // Move new app into place
            try FileManager.default.moveItem(at: newApp, to: URL(fileURLWithPath: currentAppPath))

            // Remove quarantine from installed app
            let xattr2 = Process()
            xattr2.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr2.arguments = ["-cr", currentAppPath]
            try xattr2.run()
            xattr2.waitUntilExit()

            // Restore executable permissions and ad-hoc sign bundled binaries
            let resourcesDir = currentAppPath + "/Contents/Resources"
            for binary in ["yt-dlp", "ffmpeg", "ffprobe"] {
                let binPath = resourcesDir + "/" + binary
                if FileManager.default.fileExists(atPath: binPath) {
                    let chmod = Process()
                    chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                    chmod.arguments = ["+x", binPath]
                    try chmod.run()
                    chmod.waitUntilExit()

                    // Re-sign so macOS doesn't block execution
                    let codesign = Process()
                    codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                    codesign.arguments = ["--force", "--sign", "-", "--timestamp=none", binPath]
                    try? codesign.run()
                    codesign.waitUntilExit()
                }
            }

            downloadProgress = 1.0
            updateLogger.info("Update installed successfully, relaunching...")

            // Clean up backup and temp
            try? FileManager.default.removeItem(atPath: backupPath)
            try? FileManager.default.removeItem(at: tempDir)

            // Relaunch
            relaunch()

        } catch {
            updateLogger.error("Update failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
            isDownloading = false
        }
    }

    /// Skip this version — user clicked "Skip"
    func skipVersion() {
        if let version = updateAvailable?.version {
            UserDefaults.standard.set(version, forKey: "skippedVersion")
        }
        updateAvailable = nil
    }

    // MARK: - Private

    private func downloadWithProgress(from url: URL, expectedSize: Int) async throws -> (URL, URLResponse) {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("clip_update_\(UUID().uuidString).zip")

        let delegate = DownloadProgressDelegate(expectedSize: expectedSize) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = min(progress * 0.9, 0.9)
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let request = URLRequest(url: url)

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { localURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let localURL = localURL, let response = response else {
                    continuation.resume(throwing: UpdateError.extractionFailed)
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: tempFile.path) {
                        try FileManager.default.removeItem(at: tempFile)
                    }
                    try FileManager.default.moveItem(at: localURL, to: tempFile)
                    continuation.resume(returning: (tempFile, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }

    private func relaunch() {
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let expectedSize: Int
    let onProgress: (Double) -> Void

    init(expectedSize: Int, onProgress: @escaping (Double) -> Void) {
        self.expectedSize = expectedSize
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expectedSize)
        guard total > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(total)
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled in completion handler
    }
}

enum UpdateError: LocalizedError {
    case extractionFailed
    case noAppFound

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Failed to extract update archive"
        case .noAppFound: return "No app bundle found in update"
        }
    }
}
