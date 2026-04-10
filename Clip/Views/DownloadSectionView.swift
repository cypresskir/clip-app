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
            // Glass segmented tab bar
            HStack(spacing: 0) {
                // Segmented control
                HStack(spacing: 2) {
                    ForEach(DownloadSectionTab.allCases, id: \.self) { tab in
                        GlassSegment(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(3)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )

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
                }

                if selectedTab == .history && !downloadViewModel.historyStore.entries.isEmpty {
                    ClearHistoryButton(historyStore: downloadViewModel.historyStore)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Content
            Group {
                switch selectedTab {
                case .downloads:
                    DownloadListView(selectedURL: selectedURL, onSelectURL: onSelectURL)
                        .environmentObject(downloadViewModel)
                        .transition(.opacity)
                case .history:
                    HistoryView(historyStore: downloadViewModel.historyStore, selectedURL: selectedURL, onSelectURL: onSelectURL)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
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

struct GlassSegment: View {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                isSelected
                ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                : AnyShapeStyle(.clear)
            , in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.15 : 0), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(title)
    }
}
