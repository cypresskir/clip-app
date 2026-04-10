import SwiftUI

struct FormatPickerView: View {
    @ObservedObject var item: DownloadItem
    @State private var showCustomSize = false
    @State private var customMB: String = ""
    @State private var clipToggleCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Format & Quality")
                .font(.headline)

            // Format row
            VStack(alignment: .leading, spacing: 6) {
                Text("Format")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(OutputFormat.allCases) { format in
                        SettingsPill(
                            title: format.rawValue,
                            isSelected: item.selectedFormat == format
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                item.selectedFormat = format
                                item.updateEstimatedSize()
                            }
                        }
                    }
                }
            }

            // Resolution row (hidden for audio-only)
            if !item.selectedFormat.isAudioOnly {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resolution")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        let available = item.availableResolutions
                        ForEach(OutputResolution.allCases) { res in
                            let isAvailable = available.contains(res)
                            SettingsPill(
                                title: res.displayName,
                                isSelected: item.selectedResolution == res,
                                isDisabled: !isAvailable
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    item.selectedResolution = res
                                    item.updateEstimatedSize()
                                }
                            }
                        }
                    }
                }
            }

            // Target size picker
            if !item.selectedFormat.isAudioOnly {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Size")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        SettingsPill(
                            title: "Original",
                            isSelected: item.targetSize == .none && !showCustomSize
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCustomSize = false
                                item.targetSize = .none
                            }
                        }

                        SettingsPill(
                            title: "Custom",
                            isSelected: showCustomSize || item.targetSize != .none
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCustomSize = true
                            }
                        }

                        if showCustomSize {
                            HStack(spacing: 6) {
                                TextField("MB", text: $customMB)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                                    .frame(width: 70)
                                    .onSubmit { applyCustomSize() }
                                Text("MB")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if item.targetSize != .none {
                        targetSizeInfo
                    }
                }
            }

            // Clip range
            if let duration = item.metadata?.duration, duration > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $item.clipEnabled) {
                        Label("Download clip", systemImage: "scissors")
                            .font(.subheadline)
                            .symbolEffect(.bounce, value: clipToggleCount)
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: item.clipEnabled) {
                        clipToggleCount += 1
                        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                            if item.clipEnabled && item.clipRange == nil {
                                item.clipRange = ClipRange(start: 0, end: duration)
                            }
                            item.updateEstimatedSize()
                        }
                    }

                    if item.clipEnabled {
                        ClipRangeView(item: item)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity
                                        .combined(with: .scale(scale: 0.95, anchor: .top))
                                        .combined(with: .move(edge: .top)),
                                    removal: .opacity
                                        .combined(with: .scale(scale: 0.98, anchor: .top))
                                )
                            )
                            .onChange(of: item.clipRange) {
                                item.updateEstimatedSize()
                            }
                    }
                }
            }

            // File size display
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
                Text("Estimated size:")
                    .foregroundStyle(.secondary)
                if let size = item.estimatedFileSize {
                    Text(FileSizeFormatter.format(size))
                        .fontWeight(.medium)
                    if item.targetSize != .none, let target = item.targetSize.bytes {
                        if size > target {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                            Text(FileSizeFormatter.format(target))
                                .fontWeight(.medium)
                                .foregroundStyle(ClipTheme.rosewood)
                            Text("(will compress)")
                                .font(.caption2)
                                .foregroundStyle(ClipTheme.rosewood)
                        } else {
                            Text("(already under target)")
                                .font(.caption2)
                                .foregroundStyle(ClipTheme.success)
                        }
                    }
                } else {
                    Text("Size unknown")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }

    private func applyCustomSize() {
        if let mb = Int(customMB), mb > 0 {
            item.targetSize = .custom(mb: mb)
        }
    }

    @ViewBuilder
    private var targetSizeInfo: some View {
        if let fullDuration = item.metadata?.duration, fullDuration > 0,
           let targetBytes = item.targetSize.bytes {
            let duration = (item.clipEnabled ? item.clipRange?.duration : nil) ?? fullDuration
            let audioBitrate: Double = 128_000 // 128kbps audio
            let availableForVideo = Double(targetBytes) * 8.0 - (audioBitrate * duration)
            let videoBitrate = max(availableForVideo / duration, 0)
            let videoBitrateKbps = Int(videoBitrate / 1000)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                if videoBitrateKbps < 500 {
                    Text("Very low video bitrate (\(videoBitrateKbps) kbps) — expect quality loss")
                        .foregroundStyle(ClipTheme.rosewood)
                } else {
                    Text("Target video bitrate: \(videoBitrateKbps) kbps")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
    }
}

/// Pill button used for format/resolution/target-size selection.
/// Shared between main window and menu bar.
struct SettingsPill: View {
    let title: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    isSelected
                    ? AnyShapeStyle(ClipTheme.accent)
                    : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)),
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0.2 : 0.06), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .help(isDisabled ? "Not available for this video" : "")
    }
}
