import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var downloadViewModel: DownloadViewModel
    @ObservedObject var clipboardMonitor = ClipAppDelegate.clipboardMonitor
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Clipboard suggestion
            if let detected = clipboardMonitor.detectedURL, viewModel.urlText.isEmpty {
                HStack(spacing: 6) {
                    PlatformIcon(platform: URLDetector.detectPlatform(from: detected), size: 12)
                    Text("Clipboard URL detected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Download") {
                        viewModel.urlText = detected
                        clipboardMonitor.dismiss()
                        startQuickDownload()
                    }
                    .controlSize(.small)
                    .buttonStyle(ClipProminentButtonStyle())
                    .font(.caption2)
                    Button {
                        clipboardMonitor.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss clipboard suggestion")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ClipTheme.accent.opacity(0.06))
            }

            // URL Input
            HStack(spacing: 8) {
                if viewModel.detectedPlatform != .unknown {
                    PlatformIcon(platform: viewModel.detectedPlatform, size: 14)
                }

                TextField("Paste video URL...", text: $viewModel.urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .onSubmit { startQuickDownload() }
                    .onChange(of: viewModel.urlText) { viewModel.onURLChanged() }

                Button {
                    startQuickDownload()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.isValidURL || viewModel.isProcessing)
                .accessibilityLabel("Download")
                .help("Download video (Return)")
            }
            .padding(12)

            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 8)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(ClipTheme.coral)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            // Download list
            if downloadViewModel.downloads.isEmpty {
                Text("No downloads yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(downloadViewModel.downloads.prefix(ClipConstants.menuBarMaxItems)) { item in
                            MenuBarDownloadRow(item: item)
                                .environmentObject(downloadViewModel)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }

            // Footer
            HStack(spacing: 12) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows {
                        if window.title == "Clip" {
                            window.makeKeyAndOrderFront(nil)
                            break
                        }
                    }
                } label: {
                    Text("Open Clip")
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(ClipTheme.coral)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 340)
    }

    private func startQuickDownload() {
        let url = viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLDetector.isValidURL(url) else { return }

        viewModel.isProcessing = true
        viewModel.errorMessage = nil

        Task {
            let error = await downloadViewModel.prepareAndStartDownload(
                url: url,
                platform: viewModel.detectedPlatform
            )
            if let error {
                viewModel.errorMessage = error
            } else {
                viewModel.urlText = ""
            }
            viewModel.isProcessing = false
        }
    }
}

@MainActor
class MenuBarViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var detectedPlatform: Platform = .unknown
    @Published var isProcessing = false
    @Published var errorMessage: String?

    var isValidURL: Bool {
        URLDetector.isValidURL(urlText)
    }

    func onURLChanged() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        detectedPlatform = URLDetector.detectPlatform(from: trimmed)
        errorMessage = nil
    }
}

struct MenuBarDownloadRow: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject var downloadViewModel: DownloadViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Platform icon
            PlatformIcon(platform: item.platform, size: 14)
                .frame(width: 16)

            // Title + status stacked vertically
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                statusView
            }

            Spacer(minLength: 4)

            rightAccessory
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .analyzing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Analyzing...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            Text(item.status.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)

        case .queued:
            Text("Queued")
                .font(.caption2)
                .foregroundStyle(.secondary)

        case .downloading(let progress, let speed, _):
            VStack(alignment: .leading, spacing: 3) {
                GlassProgressBar(value: progress, tint: ClipTheme.accent, height: 4)
                    .accessibilityValue("\(Int(progress * 100)) percent")
                HStack(spacing: 6) {
                    Text("\(Int(progress * 100))%")
                    if !speed.isEmpty {
                        Text(speed)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

        case .compressing(let progress):
            VStack(alignment: .leading, spacing: 3) {
                GlassProgressBar(value: progress, tint: ClipTheme.rosewood, height: 4)
                    .accessibilityValue("\(Int(progress * 100)) percent")
                Text(item.status.statusText)
                    .font(.caption2)
                    .foregroundStyle(ClipTheme.rosewood)
            }

        case .complete(let filePath):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ClipTheme.success)
                Text("Done")
                    .foregroundStyle(.secondary)
                Button("Reveal") {
                    downloadViewModel.revealInFinder(path: filePath)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
            }
            .font(.caption2)

        case .failed(let error):
            Text(error)
                .font(.caption2)
                .foregroundStyle(ClipTheme.coral)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var rightAccessory: some View {
        if item.status.isActive {
            Button {
                downloadViewModel.cancelDownload(for: item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cancel download")
        } else if case .failed = item.status {
            Button {
                downloadViewModel.retryDownload(for: item)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ClipTheme.bronze)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Retry download")
        } else if let size = item.estimatedFileSize {
            Text(FileSizeFormatter.format(size))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
    }
}
