import SwiftUI

struct URLInputView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Platform badge
                if viewModel.detectedPlatform != .unknown {
                    PlatformIcon(platform: viewModel.detectedPlatform, size: 20)
                        .frame(width: 24)
                }

                TextField("Paste video URL...", text: $viewModel.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if viewModel.isValidURL {
                            Task { await viewModel.analyze() }
                        }
                    }
                    .onChange(of: viewModel.urlText) {
                        viewModel.onURLChanged()
                    }

                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        viewModel.urlText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.onURLChanged()
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Paste URL from clipboard (Cmd+Shift+V)")

                Button {
                    Task { await viewModel.analyze() }
                } label: {
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text("Analyze")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(ClipProminentButtonStyle())
                .disabled(!viewModel.isValidURL || viewModel.isAnalyzing)
                .keyboardShortcut(.return, modifiers: .command)
                .help(viewModel.isValidURL ? "Fetch video info (Cmd+Return)" : "Enter a valid video URL first")
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ClipTheme.coral)
                    .lineLimit(2)
            }
        }
    }
}
