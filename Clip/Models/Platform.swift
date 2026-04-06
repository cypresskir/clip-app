import SwiftUI

enum Platform: String, Codable {
    case youtube
    case x
    case instagram
    case tiktok
    case unknown

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .x: return "X"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .unknown: return "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .x: return "bubble.left.fill"
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Asset catalog image name for platforms with custom icons, nil for SF Symbol fallback.
    var assetIconName: String? {
        switch self {
        case .youtube: return "PlatformYouTube"
        case .x: return "PlatformX"
        case .tiktok: return "PlatformTikTok"
        case .instagram: return "PlatformInstagram"
        default: return nil
        }
    }

    var color: Color {
        switch self {
        case .youtube: return ClipTheme.coral
        case .x: return .primary
        case .instagram: return ClipTheme.lavender
        case .tiktok: return ClipTheme.accent
        case .unknown: return .secondary
        }
    }
}

struct PlatformIcon: View {
    let platform: Platform
    var size: CGFloat = 14

    var body: some View {
        if let assetName = platform.assetIconName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: platform.iconName)
                .foregroundStyle(platform.color)
                .font(.system(size: size * 0.75))
                .frame(width: size, height: size)
        }
    }
}
