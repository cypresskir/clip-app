import SwiftUI

struct DownloadListView: View {
    @EnvironmentObject var downloadViewModel: DownloadViewModel
    var selectedURL: String
    var onSelectURL: (String) -> Void

    var body: some View {
        if downloadViewModel.downloads.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No active downloads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(downloadViewModel.downloads) { item in
                        DownloadRowView(item: item, isSelected: item.url == selectedURL)
                            .environmentObject(downloadViewModel)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectURL(item.url)
                            }
                    }
                }
            }
        }
    }
}

struct DownloadRowView: View {
    @ObservedObject var item: DownloadItem
    var isSelected: Bool = false
    @EnvironmentObject var downloadViewModel: DownloadViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Small thumbnail
            Group {
                if let data = item.thumbnailData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                }
            }
            .frame(width: 48, height: 27)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    PlatformIcon(platform: item.platform, size: 12)
                    Text(item.displayTitle)
                        .font(.caption)
                        .lineLimit(1)
                }

                // Status
                switch item.status {
                case .analyzing:
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Analyzing...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .ready:
                    Text(item.status.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                case .queued:
                    Text(item.status.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                case .downloading(let progress, let speed, let eta):
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .controlSize(.small)
                            .accessibilityValue("\(Int(progress * 100)) percent")
                        HStack {
                            Text("\(Int(progress * 100))%")
                            if !speed.isEmpty { Text("· \(speed)") }
                            if !eta.isEmpty { Text("· ETA \(eta)") }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                case .compressing(let progress):
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .controlSize(.small)
                            .tint(ClipTheme.rosewood)
                            .accessibilityValue("\(Int(progress * 100)) percent")
                        Text(item.status.statusText)
                            .font(.caption2)
                            .foregroundStyle(ClipTheme.rosewood)
                    }

                case .complete(let filePath):
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ClipTheme.success)
                        Text("Complete")
                            .foregroundStyle(.secondary)
                        Button("Show in Finder") {
                            downloadViewModel.revealInFinder(path: filePath)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                    .font(.caption2)

                case .failed(let error):
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(ClipTheme.coral)
                        Text(error)
                            .foregroundStyle(ClipTheme.coral)
                            .lineLimit(1)
                        Button("Retry") {
                            downloadViewModel.retryDownload(for: item)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .accessibilityLabel("Retry download")
                    }
                    .font(.caption2)
                }
            }

            Spacer()

            // Cancel button for active downloads
            if item.status.isActive {
                Button {
                    downloadViewModel.cancelDownload(for: item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel download")
            }

            // File size
            if let size = item.estimatedFileSize {
                Text(FileSizeFormatter.format(size))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(isSelected ? ClipTheme.accent.opacity(0.1) : Color(.controlBackgroundColor))
    }
}
