import SwiftUI

struct ContentView: View {
    @StateObject private var mainViewModel = MainViewModel()
    @EnvironmentObject var downloadViewModel: DownloadViewModel
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            // Update banner
            UpdateBannerView(updateService: ClipAppDelegate.updateService)

            // URL Input
            URLInputView(viewModel: mainViewModel)
                .padding()

            Divider()

            // Video Preview + Format Picker
            if let item = mainViewModel.currentItem {
                ScrollView {
                    VStack(spacing: 16) {
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
                    .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if !mainViewModel.isAnalyzing {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: isDragOver ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(isDragOver ? AnyShapeStyle(ClipTheme.accent) : AnyShapeStyle(.tertiary))
                    Text(isDragOver ? "Drop URL here" : "Paste a video URL to get started")
                        .foregroundStyle(isDragOver ? .primary : .secondary)
                        .font(.subheadline)
                    Spacer()
                }
            }

            Divider()

            // Downloads + History section with folder tabs
            DownloadSectionView(selectedURL: mainViewModel.urlText, onSelectURL: { url in
                mainViewModel.loadURL(url)
            })
                .environmentObject(downloadViewModel)
                .frame(minHeight: 180, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 500)
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
