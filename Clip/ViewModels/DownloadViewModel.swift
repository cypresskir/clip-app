import SwiftUI
import UserNotifications
import os

private let downloadLogger = Logger(subsystem: "com.clip.app", category: "downloads")

@MainActor
class DownloadViewModel: ObservableObject {
    @Published var downloads: [DownloadItem] = []
    @Published var saveDirectory: String

    let historyStore = DownloadHistoryStore()
    private let ytdlpService = YTDLPService()
    private let saveDirectoryKey = "clipSaveDirectory"

    var maxConcurrent: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxConcurrentDownloads")
        return stored > 0 ? stored : ClipConstants.defaultMaxConcurrentDownloads
    }

    var activeDownloadCount: Int {
        downloads.filter { $0.status.isActive }.count
    }

    var overallProgress: Double? {
        let active = downloads.filter {
            if case .downloading = $0.status { return true }
            return false
        }
        guard !active.isEmpty else { return nil }
        let total = active.reduce(0.0) { sum, item in
            if case .downloading(let p, _, _) = item.status { return sum + p }
            return sum
        }
        return total / Double(active.count)
    }

    init() {
        let defaultDir = NSHomeDirectory() + "/Downloads/Clip"
        self.saveDirectory = UserDefaults.standard.string(forKey: saveDirectoryKey) ?? defaultDir
        ensureSaveDirectoryExists()
    }

    func setSaveDirectory(_ path: String) {
        saveDirectory = path
        UserDefaults.standard.set(path, forKey: saveDirectoryKey)
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose download folder"

        if panel.runModal() == .OK, let url = panel.url {
            setSaveDirectory(url.path)
        }
    }

    func startDownload(for item: DownloadItem) {
        let downloadItem: DownloadItem

        if case .ready = item.status {
            downloadItem = item
        } else {
            // Item already used — clone with current settings for a new download
            downloadItem = item.cloneForRedownload()
        }

        if !downloads.contains(where: { $0.id == downloadItem.id }) {
            downloads.insert(downloadItem, at: 0)
        }

        // Queue if at concurrent limit
        if activeDownloadCount >= maxConcurrent {
            downloadItem.status = .queued
            return
        }

        beginDownload(for: downloadItem)
    }

    private func beginDownload(for item: DownloadItem) {
        downloadLogger.info("Starting download: \(item.downloadURL, privacy: .public)")
        ensureSaveDirectoryExists()

        let formatId = item.bestFormatId(for: item.selectedFormat, resolution: item.selectedResolution)
        let clipRange = item.clipEnabled ? item.clipRange : nil

        let itemId = item.id
        do {
            // Use Reddit post title for filename when downloading resolved URLs
            let titleOverride = item.resolvedURL != nil ? item.metadata?.title : nil

            let process = try ytdlpService.startDownload(
                url: item.downloadURL,
                formatId: formatId,
                outputFormat: item.selectedFormat,
                resolution: item.selectedResolution,
                clipRange: clipRange,
                titleOverride: titleOverride,
                outputDirectory: saveDirectory,
                onProgress: { [weak self] percent, speed, eta in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if let item = self.downloads.first(where: { $0.id == itemId }) {
                            item.status = .downloading(progress: percent / 100.0, speed: speed, eta: eta)
                            item.objectWillChange.send()
                            self.objectWillChange.send()
                        }
                    }
                },
                onComplete: { [weak self] filePath, errorMessage in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if let item = self.downloads.first(where: { $0.id == itemId }) {
                            // If user already cancelled, don't overwrite the status
                            guard !item.isCancelled else { return }
                            if let path = filePath {
                                self.handleDownloadComplete(item: item, filePath: path)
                            } else {
                                item.status = .failed(error: errorMessage ?? "Download failed")
                                item.objectWillChange.send()
                                self.objectWillChange.send()
                                self.startNextQueued()
                            }
                        }
                    }
                }
            )
            item.process = process
            item.status = .downloading(progress: 0, speed: "", eta: "")
        } catch {
            downloadLogger.error("Download failed to start: \(error.localizedDescription, privacy: .public)")
            item.status = .failed(error: error.localizedDescription)
            startNextQueued()
        }
    }

    private func startNextQueued() {
        guard activeDownloadCount < maxConcurrent else { return }
        guard let next = downloads.first(where: { $0.status == .queued }) else { return }
        downloadLogger.debug("Dequeuing next download: \(next.url, privacy: .public)")
        beginDownload(for: next)
    }

    private func handleDownloadComplete(item: DownloadItem, filePath: String) {
        // Check if compression is needed
        guard let targetBytes = item.targetSize.bytes else {
            finishItem(item, filePath: filePath)
            return
        }

        // Check actual file size
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: filePath),
              let fileSize = attrs[.size] as? Int64,
              fileSize > targetBytes else {
            // Already under target
            finishItem(item, filePath: filePath)
            return
        }

        guard FFmpegService.isAvailable else {
            // No ffmpeg — complete without compression
            finishItem(item, filePath: filePath)
            return
        }

        // Start compression
        item.status = .compressing(progress: 0)
        item.objectWillChange.send()
        objectWillChange.send()

        let itemId = item.id
        FFmpegService.compress(
            inputPath: filePath,
            targetBytes: targetBytes,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    guard let self = self,
                          let item = self.downloads.first(where: { $0.id == itemId }) else { return }
                    item.status = .compressing(progress: progress)
                    item.objectWillChange.send()
                    self.objectWillChange.send()
                }
            },
            onComplete: { [weak self] result in
                Task { @MainActor in
                    guard let self = self,
                          let item = self.downloads.first(where: { $0.id == itemId }) else { return }
                    switch result {
                    case .success(let compressedPath):
                        self.finishItem(item, filePath: compressedPath)
                    case .failure(let error):
                        // Compression failed — still complete with original file
                        item.status = .complete(filePath: filePath)
                        self.historyStore.add(DownloadHistoryEntry(from: item, filePath: filePath))
                        self.sendNotification(title: "\(item.displayTitle) (compression failed: \(error.localizedDescription))")
                        item.objectWillChange.send()
                        self.objectWillChange.send()
                        self.startNextQueued()
                    }
                }
            }
        )
    }

    private func finishItem(_ item: DownloadItem, filePath: String) {
        item.status = .complete(filePath: filePath)
        historyStore.add(DownloadHistoryEntry(from: item, filePath: filePath))
        sendNotification(title: item.displayTitle)
        item.objectWillChange.send()
        objectWillChange.send()
        startNextQueued()
    }

    func terminateAll() {
        for item in downloads where item.status.isActive {
            item.process?.terminate()
            item.process = nil
        }
    }

    func cancelDownload(for item: DownloadItem) {
        item.isCancelled = true
        item.process?.terminate()
        item.process = nil
        item.status = .failed(error: "Cancelled")
        item.objectWillChange.send()
        objectWillChange.send()
        startNextQueued()
    }

    func retryDownload(for item: DownloadItem) {
        item.status = .ready
        item.process = nil
        item.isCancelled = false
        startDownload(for: item)
    }

    /// Shared logic for menu bar and main window: fetch metadata, configure, and start download.
    /// Returns the error message on failure, or nil on success.
    func prepareAndStartDownload(url: String, platform: Platform) async -> String? {
        let normalized = URLDetector.normalizeURL(url)
        if downloads.contains(where: { URLDetector.normalizeURL($0.url) == normalized && $0.status.isActive }) {
            return "This URL is already downloading"
        }

        let item = DownloadItem(url: url, platform: platform)
        downloads.insert(item, at: 0)

        do {
            // Resolve Reddit URLs to direct video URLs
            var fetchURL = url
            if RedditResolver.isRedditURL(url) {
                let resolved = try await RedditResolver.resolve(url)
                fetchURL = resolved.videoURL
                item.resolvedURL = fetchURL
            }

            let service = YTDLPService()
            let metadata = try await service.fetchMetadata(url: fetchURL)
            item.metadata = metadata
            item.status = .ready

            if let thumbURL = metadata.thumbnail.flatMap({ URL(string: $0) }) {
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: thumbURL) {
                        item.thumbnailData = data
                    }
                }
            }

            // Apply preferred settings
            let preferredFormat = OutputFormat(rawValue: UserDefaults.standard.string(forKey: "preferredFormat") ?? "MP4") ?? .mp4
            let prefResRaw = UserDefaults.standard.integer(forKey: "preferredResolution")
            let preferredResolution = OutputResolution(rawValue: prefResRaw == 0 ? 1080 : prefResRaw) ?? .p1080

            item.selectedFormat = preferredFormat
            if item.availableResolutions.contains(preferredResolution) {
                item.selectedResolution = preferredResolution
            } else if let highest = item.availableResolutions.first {
                item.selectedResolution = highest
            }
            item.updateEstimatedSize()

            startDownload(for: item)
            return nil
        } catch {
            let friendly = YTDLPService.friendlyError(error.localizedDescription)
            item.status = .failed(error: friendly)
            return friendly
        }
    }

    func isDuplicate(url: String) -> Bool {
        let normalized = URLDetector.normalizeURL(url)
        return downloads.contains { URLDetector.normalizeURL($0.url) == normalized && $0.status.isActive }
    }

    func removeCompleted() {
        downloads.removeAll { item in
            if case .complete = item.status { return true }
            return false
        }
    }

    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func ensureSaveDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: saveDirectory) {
            try? fm.createDirectory(atPath: saveDirectory, withIntermediateDirectories: true)
        }
    }

    private func sendNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
