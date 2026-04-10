import SwiftUI

struct UpdateBannerView: View {
    @ObservedObject var updateService: UpdateService

    var body: some View {
        if let release = updateService.updateAvailable {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.app.fill")
                        .foregroundStyle(ClipTheme.accent)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clip \(release.version) available")
                            .font(.caption)
                            .fontWeight(.semibold)
                        if let notes = release.body, !notes.isEmpty {
                            Text(notes.prefix(80) + (notes.count > 80 ? "..." : ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if updateService.isDownloading {
                        GlassProgressBar(value: updateService.downloadProgress, tint: ClipTheme.accent)
                            .frame(width: 60)
                        Text("\(Int(updateService.downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    } else {
                        Button("Skip") {
                            updateService.skipVersion()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Button("Update") {
                            Task { await updateService.downloadAndInstall() }
                        }
                        .buttonStyle(ClipProminentButtonStyle())
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }

        if let error = updateService.error {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ClipTheme.coral)
                    .font(.caption)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(ClipTheme.coral)
                Spacer()
                Button("Dismiss") { updateService.error = nil }
                    .buttonStyle(.borderless)
                    .font(.caption2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(ClipTheme.coral.opacity(0.06))
        }
    }
}
