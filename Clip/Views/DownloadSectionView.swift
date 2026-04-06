import SwiftUI

enum DownloadSectionTab: String, CaseIterable {
    case downloads = "Downloads"
    case history = "History"

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .history: return "clock"
        }
    }
}

struct DownloadSectionView: View {
    @EnvironmentObject var downloadViewModel: DownloadViewModel
    var selectedURL: String
    var onSelectURL: (String) -> Void
    @State private var selectedTab: DownloadSectionTab = .downloads
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Folder tab bar
            HStack(spacing: 0) {
                ForEach(DownloadSectionTab.allCases, id: \.self) { tab in
                    FolderTab(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }

                Spacer()

                // Context action for current tab
                if selectedTab == .downloads && !downloadViewModel.downloads.isEmpty {
                    Button("Clear completed") {
                        showClearConfirmation = true
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .confirmationDialog("Remove all completed downloads from the list?", isPresented: $showClearConfirmation) {
                        Button("Clear Completed", role: .destructive) {
                            downloadViewModel.removeCompleted()
                        }
                    }
                    .padding(.trailing, 12)
                }

                if selectedTab == .history && !downloadViewModel.historyStore.entries.isEmpty {
                    ClearHistoryButton(historyStore: downloadViewModel.historyStore)
                        .padding(.trailing, 12)
                }
            }
            .padding(.leading, 4)

            // Divider sits flush under the tabs
            Rectangle()
                .fill(.separator)
                .frame(height: 1)

            // Content
            Group {
                switch selectedTab {
                case .downloads:
                    DownloadListView(selectedURL: selectedURL, onSelectURL: onSelectURL)
                        .environmentObject(downloadViewModel)
                case .history:
                    HistoryView(historyStore: downloadViewModel.historyStore, selectedURL: selectedURL, onSelectURL: onSelectURL)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ClearHistoryButton: View {
    @ObservedObject var historyStore: DownloadHistoryStore
    @State private var showConfirmation = false

    var body: some View {
        Button("Clear All") {
            showConfirmation = true
        }
        .font(.caption2)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .confirmationDialog("Remove all download history?", isPresented: $showConfirmation) {
            Button("Clear All History", role: .destructive) {
                historyStore.clear()
            }
        }
    }
}

struct FolderTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 6,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 6
                )
                .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : .clear)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 6,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 6
                )
                .stroke(isSelected ? AnyShapeStyle(.separator) : AnyShapeStyle(.clear), lineWidth: 1)
            )
            // Hide the bottom border of the selected tab so it merges with content
            .offset(y: isSelected ? 1 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
