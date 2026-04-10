import SwiftUI

struct VideoPreviewView: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Thumbnail
            Group {
                if let data = item.thumbnailData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay {
                            if case .analyzing = item.status {
                                ProgressView()
                            } else {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                }
            }
            .frame(width: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Metadata
            VStack(alignment: .leading, spacing: 8) {
                // Platform badge
                HStack(spacing: 4) {
                    PlatformIcon(platform: item.platform, size: 14)
                    Text(item.platform.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(item.platform.assetIconName != nil ? .primary : item.platform.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.platform.color.opacity(0.1), in: Capsule(style: .continuous))

                // Title
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                if let metadata = item.metadata {
                    HStack(spacing: 12) {
                        Label(metadata.formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let date = metadata.formattedUploadDate {
                            Label(date, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .glassCard()
    }
}
