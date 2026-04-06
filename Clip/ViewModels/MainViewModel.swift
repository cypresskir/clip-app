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
            errorMessage = "Unsupported URL. Paste a YouTube, X, or Instagram link."
            return
        }

        errorMessage = nil
        isAnalyzing = true

        let item = DownloadItem(url: trimmed, platform: detectedPlatform)
        item.status = .analyzing
        currentItem = item

        do {
            let metadata = try await ytdlpService.fetchMetadata(url: trimmed)
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
