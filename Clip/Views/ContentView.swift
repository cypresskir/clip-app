import SwiftUI

struct ContentView: View {
    @StateObject private var mainViewModel = MainViewModel()
    @EnvironmentObject var downloadViewModel: DownloadViewModel
    @State private var isDragOver = false
    @State private var downloadSectionHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            // Update banner
            UpdateBannerView(updateService: ClipAppDelegate.updateService)

            // URL Input
            URLInputView(viewModel: mainViewModel)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // Video Preview + Format Picker
            if let item = mainViewModel.currentItem {
                ScrollView {
                    VStack(spacing: 12) {
                        VideoPreviewView(item: item)

                        if item.metadata != nil {
                            FormatPickerView(item: item)

                            // Save location
                            SaveLocationView()
                                .environmentObject(downloadViewModel)

                            // Download button
                            DownloadButtonView(item: item)
                                .environmentObject(downloadViewModel)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            } else if !mainViewModel.isAnalyzing {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: isDragOver ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(isDragOver ? AnyShapeStyle(ClipTheme.accent) : AnyShapeStyle(.tertiary))
                    Text(isDragOver ? "Drop URL here" : "Paste a video URL to get started")
                        .foregroundStyle(isDragOver ? .primary : .secondary)
                        .font(.subheadline)
                    Spacer()
                }
            }

            // Draggable divider — glass-style thin separator
            Rectangle()
                .fill(Color.clear)
                .frame(height: 8)
                .contentShape(Rectangle())
                .overlay(
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 36, height: 4)
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let delta = -value.translation.height
                            downloadSectionHeight = max(100, min(400, downloadSectionHeight + delta))
                        }
                )

            // Downloads + History section
            DownloadSectionView(selectedURL: mainViewModel.urlText, onSelectURL: { url in
                mainViewModel.loadURL(url)
            })
                .environmentObject(downloadViewModel)
                .frame(height: downloadSectionHeight)
        }
        .background(TranslucentWindowBackground())
        .frame(minWidth: 500, minHeight: 600)
        .onDrop(of: [.url, .text], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            mainViewModel.urlText = url.absoluteString
                            mainViewModel.onURLChanged()
                            if mainViewModel.isValidURL {
                                await mainViewModel.analyze()
                            }
                        }
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    if let text = text {
                        Task { @MainActor in
                            mainViewModel.urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            mainViewModel.onURLChanged()
                            if mainViewModel.isValidURL {
                                await mainViewModel.analyze()
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

/// White window with 5% transparency.
struct TranslucentWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = NSColor.white.withAlphaComponent(0.95)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct DownloadButtonView: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject var downloadViewModel: DownloadViewModel

    var body: some View {
        Button {
            downloadViewModel.startDownload(for: item)
        } label: {
            Label("Download", systemImage: "arrow.down.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ClipProminentButtonStyle())
        .disabled(item.metadata == nil)
        .help(item.metadata == nil ? "Waiting for video analysis" : "Start downloading")
    }
}
