import Foundation

enum DownloadStatus: Equatable {
    case analyzing
    case ready
    case queued
    case downloading(progress: Double, speed: String, eta: String)
    case compressing(progress: Double)
    case complete(filePath: String)
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .analyzing, .downloading, .queued, .compressing: return true
        default: return false
        }
    }

    var statusText: String {
        switch self {
        case .analyzing: return "Analyzing..."
        case .ready: return "Ready"
        case .queued: return "Queued"
        case .downloading(let progress, _, _): return "Downloading \(Int(progress * 100))%"
        case .compressing(let progress): return "Compressing \(Int(progress * 100))%"
        case .complete: return "Complete"
        case .failed(let error): return error
        }
    }
}

enum TargetFileSize: Equatable, Hashable {
    case none
    case custom(mb: Int)

    var bytes: Int64? {
        switch self {
        case .none: return nil
        case .custom(let mb): return Int64(mb) * 1_000_000
        }
    }

    var displayName: String {
        switch self {
        case .none: return "Original"
        case .custom(let mb): return "\(mb) MB"
        }
    }
}

struct ClipRange: Equatable {
    var start: Double  // seconds
    var end: Double    // seconds

    var duration: Double { max(end - start, 0) }

    /// Format seconds as HH:MM:SS or MM:SS
    static func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Format as HH:MM:SS.ss for yt-dlp --download-sections
    static func formatTimePrecise(_ seconds: Double) -> String {
        let total = max(seconds, 0)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = total - Double(h * 3600 + m * 60)
        return String(format: "%02d:%02d:%05.2f", h, m, s)
    }
}

@MainActor
class DownloadItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: String
    let platform: Platform
    /// For Reddit URLs: the resolved v.redd.it or external video URL
    var resolvedURL: String?

    @Published var status: DownloadStatus = .analyzing
    @Published var metadata: VideoMetadata?
    @Published var selectedFormat: OutputFormat = .mp4
    @Published var selectedResolution: OutputResolution = .p1080
    @Published var targetSize: TargetFileSize = .none
    @Published var estimatedFileSize: Int64?
    @Published var thumbnailData: Data?
    @Published var clipEnabled: Bool = false
    @Published var clipRange: ClipRange?
    var isCancelled = false

    var process: Process?

    init(url: String, platform: Platform) {
        self.url = url
        self.platform = platform
    }

    var displayTitle: String {
        metadata?.title ?? "Loading..."
    }

    var availableResolutions: [OutputResolution] {
        guard let metadata = metadata else { return [] }
        let heights = Set(metadata.formats.compactMap { $0.height })
        return OutputResolution.allCases.filter { heights.contains($0.rawValue) }
    }

    func bestFormatId(for format: OutputFormat, resolution: OutputResolution) -> String? {
        guard let metadata = metadata else { return nil }

        if format.isAudioOnly {
            let audioFormats = metadata.formats
                .filter { !$0.hasVideo && $0.hasAudio }
                .sorted { ($0.tbr ?? 0) > ($1.tbr ?? 0) }
            return audioFormats.first?.formatId
        }

        let targetExt: String
        switch format {
        case .mp4, .mov: targetExt = "mp4"
        case .webm: targetExt = "webm"
        case .mp3: targetExt = "m4a"
        }

        let matching = metadata.formats
            .filter { $0.hasVideo && $0.height == resolution.rawValue }
            .filter { $0.ext == targetExt || format == .mov }
            .sorted { Self.codecPriority($0) > Self.codecPriority($1) }

        if let match = matching.first { return match.formatId }

        let fallback = metadata.formats
            .filter { $0.hasVideo && $0.height == resolution.rawValue }
            .sorted { Self.codecPriority($0) > Self.codecPriority($1) }
        return fallback.first?.formatId
    }

    /// Prefer AV1 > VP9 > AVC for better compression efficiency at same quality
    private static func codecPriority(_ format: VideoFormat) -> Int {
        let codec = format.vcodec ?? ""
        if codec.hasPrefix("av01") { return 3 }
        if codec.hasPrefix("vp9") || codec.hasPrefix("vp09") { return 2 }
        if codec.hasPrefix("avc") { return 1 }
        return 0
    }

    func estimateFileSize(for format: OutputFormat, resolution: OutputResolution) -> Int64? {
        guard let metadata = metadata else { return nil }
        let duration = metadata.duration ?? 0

        if format.isAudioOnly {
            let audioFormats = metadata.formats
                .filter { !$0.hasVideo && $0.hasAudio }
                .sorted { ($0.tbr ?? 0) > ($1.tbr ?? 0) }
            if let best = audioFormats.first {
                var size: Int64?
                if let s = best.estimatedSize { size = s }
                else if let tbr = best.tbr, duration > 0 {
                    size = Int64(tbr * 1000.0 * duration / 8.0)
                }
                if var s = size {
                    if clipEnabled, let clip = clipRange, duration > 0 {
                        s = Int64(Double(s) * (clip.duration / duration))
                    }
                    return s
                }
            }
            return nil
        }

        let videoFormats = metadata.formats
            .filter { $0.hasVideo && $0.height == resolution.rawValue }
            .sorted { ($0.tbr ?? 0) > ($1.tbr ?? 0) }

        let audioFormats = metadata.formats
            .filter { !$0.hasVideo && $0.hasAudio }
            .sorted { ($0.tbr ?? 0) > ($1.tbr ?? 0) }

        var totalSize: Int64 = 0

        if let video = videoFormats.first {
            if let size = video.estimatedSize {
                totalSize += size
            } else if let tbr = video.tbr, duration > 0 {
                totalSize += Int64(tbr * 1000.0 * duration / 8.0)
            } else {
                return nil
            }
        } else {
            return nil
        }

        if let audio = audioFormats.first {
            if let size = audio.estimatedSize {
                totalSize += size
            } else if let tbr = audio.tbr, duration > 0 {
                totalSize += Int64(tbr * 1000.0 * duration / 8.0)
            }
        }

        // Scale by clip range if enabled
        if clipEnabled, let clip = clipRange, let dur = metadata.duration, dur > 0 {
            let ratio = clip.duration / dur
            totalSize = Int64(Double(totalSize) * ratio)
        }

        return totalSize
    }

    func updateEstimatedSize() {
        estimatedFileSize = estimateFileSize(for: selectedFormat, resolution: selectedResolution)
    }

    /// Create a new item with the same settings, ready for a fresh download.
    /// The URL that should be passed to yt-dlp (resolved URL for Reddit, original URL otherwise)
    var downloadURL: String {
        resolvedURL ?? url
    }

    func cloneForRedownload() -> DownloadItem {
        let clone = DownloadItem(url: url, platform: platform)
        clone.resolvedURL = resolvedURL
        clone.metadata = metadata
        clone.thumbnailData = thumbnailData
        clone.selectedFormat = selectedFormat
        clone.selectedResolution = selectedResolution
        clone.targetSize = targetSize
        clone.clipEnabled = clipEnabled
        clone.clipRange = clipRange
        clone.status = .ready
        clone.updateEstimatedSize()
        return clone
    }
}
