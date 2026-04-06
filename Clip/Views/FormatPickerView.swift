import SwiftUI

struct FormatPickerView: View {
    @ObservedObject var item: DownloadItem
    @State private var showCustomSize = false
    @State private var customMB: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format & Quality")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                // Format column
                VStack(alignment: .leading, spacing: 4) {
                    Text("Format")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(OutputFormat.allCases) { format in
                        FormatButton(
                            title: format.rawValue,
                            subtitle: format.subtitle,
                            isSelected: item.selectedFormat == format
                        ) {
                            item.selectedFormat = format
                            item.updateEstimatedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Resolution column (hidden for audio-only)
                if !item.selectedFormat.isAudioOnly {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Resolution")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let available = item.availableResolutions
                        ForEach(OutputResolution.allCases) { res in
                            let isAvailable = available.contains(res)
                            FormatButton(
                                title: res.displayName,
                                subtitle: nil,
                                isSelected: item.selectedResolution == res,
                                isDisabled: !isAvailable
                            ) {
                                item.selectedResolution = res
                                item.updateEstimatedSize()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Target size picker
            if !item.selectedFormat.isAudioOnly {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Size")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        TargetSizeButton(
                            title: "Original",
                            isSelected: item.targetSize == .none && !showCustomSize
                        ) {
                            showCustomSize = false
                            item.targetSize = .none
                        }

                        TargetSizeButton(
                            title: "Custom",
                            isSelected: showCustomSize || item.targetSize != .none
                        ) {
                            showCustomSize = true
                        }
                    }

                    if showCustomSize {
                        HStack(spacing: 6) {
                            TextField("MB", text: $customMB)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onSubmit { applyCustomSize() }
                            Text("MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Apply") { applyCustomSize() }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
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
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: item.clipEnabled) {
                        if item.clipEnabled && item.clipRange == nil {
                            item.clipRange = ClipRange(start: 0, end: duration)
                        }
                        item.updateEstimatedSize()
                    }

                    if item.clipEnabled {
                        ClipRangeView(item: item)
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
            .padding(.top, 4)
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func applyCustomSize() {
        if let mb = Int(customMB), mb > 0 {
            item.targetSize = .custom(mb: mb)
        }
    }

    @ViewBuilder
    private var targetSizeInfo: some View {
        if let duration = item.metadata?.duration, duration > 0,
           let targetBytes = item.targetSize.bytes {
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

struct TargetSizeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(isSelected ? ClipTheme.accent.opacity(0.15) : Color.secondary.opacity(0.08))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct FormatButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? ClipTheme.accent : .gray)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? ClipTheme.accent.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .help(isDisabled ? "Not available for this video" : "")
    }
}
