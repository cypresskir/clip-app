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
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                        if item.metadata != nil {
                            FormatPickerView(item: item)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))

                            // Save location
                            SaveLocationView()
                                .environmentObject(downloadViewModel)
                                .transition(.opacity)

                            // Download button
                            DownloadButtonView(item: item)
                                .environmentObject(downloadViewModel)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .animation(.easeOut(duration: 0.3), value: item.metadata != nil)
                }
                .transition(.opacity)
            } else if !mainViewModel.isAnalyzing {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: isDragOver ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(isDragOver ? AnyShapeStyle(ClipTheme.accent) : AnyShapeStyle(.tertiary))
                        .animation(.easeInOut(duration: 0.2), value: isDragOver)
                    Text(isDragOver ? "Drop URL here" : "Paste a video URL to get started")
                        .foregroundStyle(isDragOver ? .primary : .secondary)
                        .font(.subheadline)
                        .animation(.easeInOut(duration: 0.2), value: isDragOver)
                    Spacer()
                }
                .transition(.opacity)
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

/// Window background with 5% transparency, adapts to light/dark mode.
struct TranslucentWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowBackgroundView()
        DispatchQueue.main.async {
            view.configureWindow()
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowBackgroundView: NSView {
    private var appearanceObserver: NSKeyValueObservation?
    private var closeInterceptor: WindowCloseInterceptor?

    func configureWindow() {
        guard let window = self.window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("ClipMainWindow")
        window.isOpaque = false
        applyBackground(to: window)

        // Hide on close instead of destroy, so "Open Clip" can always find it
        let interceptor = WindowCloseInterceptor()
        closeInterceptor = interceptor
        window.delegate = interceptor

        appearanceObserver = window.observe(\.effectiveAppearance) { [weak self] window, _ in
            self?.applyBackground(to: window)
        }
    }

    private func applyBackground(to window: NSWindow) {
        let isDark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            // Resolve dynamic color within the dark appearance context
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                if let resolved = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) {
                    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
                }
            }
            window.backgroundColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 0.95)
        } else {
            window.backgroundColor = NSColor.windowBackgroundColor
        }
    }
}

/// Intercepts window close to hide instead of destroy.
private class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
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
