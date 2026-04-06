import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: DownloadHistoryStore
    var selectedURL: String
    var onSelectURL: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if historyStore.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No download history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(historyStore.entries) { entry in
                        HistoryRowView(entry: entry)
                            .listRowBackground(entry.url == selectedURL ? ClipTheme.accent.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectURL(entry.url)
                            }
                    }
                    .onDelete { offsets in
                        historyStore.remove(at: offsets)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct HistoryRowView: View {
    let entry: DownloadHistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(entry.platform)
                    Text(entry.resolution)
                    Text(entry.format)
                    if let size = entry.fileSize {
                        Text(FileSizeFormatter.format(size))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.completedAt, style: .date)
                Text(entry.completedAt, style: .time)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Button {
                let url = URL(fileURLWithPath: entry.filePath)
                if FileManager.default.fileExists(atPath: entry.filePath) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reveal in Finder")
            .help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }
}
