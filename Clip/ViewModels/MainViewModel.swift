import SwiftUI

@MainActor
class MainViewModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var detectedPlatform: Platform = .unknown
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var currentItem: DownloadItem?

    private let ytdlpService = YTDLPService()

    private var preferredFormat: OutputFormat {
        let raw = UserDefaults.standard.string(forKey: "preferredFormat") ?? "MP4"
        return OutputFormat(rawValue: raw) ?? .mp4
    }

    private var preferredResolution: OutputResolution {
        let raw = UserDefaults.standard.integer(forKey: "preferredResolution")
        return OutputResolution(rawValue: raw == 0 ? 1080 : raw) ?? .p1080
    }

    var isValidURL: Bool {
        URLDetector.isValidURL(urlText)
    }

    func onURLChanged() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        detectedPlatform = URLDetector.detectPlatform(from: trimmed)
        errorMessage = nil
    }

    func loadURL(_ url: String) {
        urlText = url
        onURLChanged()
        Task { await analyze() }
    }

    func analyze() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLDetector.isValidURL(trimmed) else {
            errorMessage = "Invalid URL. Paste a valid video link."
            return
        }

        errorMessage = nil
        isAnalyzing = true

        let item = DownloadItem(url: trimmed, platform: detectedPlatform)
        item.status = .analyzing
        currentItem = item

        do {
            // Reddit URLs need preprocessing — yt-dlp's Reddit extractor is broken
            var resolvedURL = trimmed
            var redditInfo: ResolvedRedditVideo?
            if RedditResolver.isRedditURL(trimmed) {
                let resolved = try await RedditResolver.resolve(trimmed)
                resolvedURL = resolved.videoURL
                item.resolvedURL = resolvedURL
                redditInfo = resolved
            }

            var metadata = try await ytdlpService.fetchMetadata(url: resolvedURL)

            // Override yt-dlp metadata with Reddit post info (HLS streams have no useful titles)
            if let reddit = redditInfo {
                metadata.title = reddit.title
                if let dur = reddit.duration, metadata.duration == nil {
                    metadata.duration = dur
                }
                if metadata.thumbnail == nil, let thumb = reddit.thumbnailURL {
                    metadata.thumbnail = thumb
                }
            }

            item.metadata = metadata
            item.status = .ready

            // Load thumbnail
            if let thumbnailURLString = metadata.thumbnail,
               let thumbnailURL = URL(string: thumbnailURLString) {
                Task {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
                        item.thumbnailData = data
                    } catch {
                        // Thumbnail loading failure is non-critical
                    }
                }
            }

            // Apply preferred format
            item.selectedFormat = preferredFormat

            // Apply preferred resolution, or fall back to highest available
            if item.availableResolutions.contains(preferredResolution) {
                item.selectedResolution = preferredResolution
            } else if let highest = item.availableResolutions.first {
                item.selectedResolution = highest
            }
            item.updateEstimatedSize()
        } catch {
            let friendly = YTDLPService.friendlyError(error.localizedDescription)
            item.status = .failed(error: friendly)
            errorMessage = friendly
        }

        isAnalyzing = false
    }
}
