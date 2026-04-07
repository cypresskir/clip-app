import Foundation

struct VideoMetadata: Codable {
    var title: String?
    var thumbnail: String?
    var duration: Double?
    let uploadDate: String?
    let formats: [VideoFormat]

    enum CodingKeys: String, CodingKey {
        case title
        case thumbnail
        case duration
        case uploadDate = "upload_date"
        case formats
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedUploadDate: String? {
        guard let uploadDate = uploadDate, uploadDate.count == 8 else { return uploadDate }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        guard let date = formatter.date(from: uploadDate) else { return uploadDate }
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        return displayFormatter.string(from: date)
    }
}

struct VideoFormat: Codable {
    let formatId: String
    let ext: String
    let resolution: String?
    let filesize: Int64?
    let filesizeApprox: Int64?
    let tbr: Double?
    let vcodec: String?
    let acodec: String?
    let height: Int?
    let width: Int?
    let formatNote: String?

    enum CodingKeys: String, CodingKey {
        case formatId = "format_id"
        case ext
        case resolution
        case filesize
        case filesizeApprox = "filesize_approx"
        case tbr
        case vcodec
        case acodec
        case height
        case width
        case formatNote = "format_note"
    }

    var hasVideo: Bool {
        guard let vcodec = vcodec else { return false }
        return vcodec != "none"
    }

    var hasAudio: Bool {
        guard let acodec = acodec else { return false }
        return acodec != "none"
    }

    var estimatedSize: Int64? {
        if let filesize = filesize, filesize > 0 { return filesize }
        if let filesizeApprox = filesizeApprox, filesizeApprox > 0 { return filesizeApprox }
        return nil
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"
    case webm = "WebM"
    case mp3 = "MP3"

    var id: String { rawValue }

    var isAudioOnly: Bool { self == .mp3 }

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .webm: return "webm"
        case .mp3: return "mp3"
        }
    }

    var subtitle: String {
        switch self {
        case .mp4: return "H.264 + AAC"
        case .mov: return "H.264 + AAC"
        case .webm: return "VP9 + Opus"
        case .mp3: return "Audio only"
        }
    }
}

enum OutputResolution: Int, CaseIterable, Identifiable {
    case p2160 = 2160
    case p1080 = 1080
    case p720 = 720
    case p480 = 480
    case p360 = 360

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .p2160: return "4K"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
}
