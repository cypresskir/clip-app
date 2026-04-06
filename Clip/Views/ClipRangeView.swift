import SwiftUI

struct ClipRangeView: View {
    @ObservedObject var item: DownloadItem
    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 32

    private var duration: Double {
        item.metadata?.duration ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timecode bar
            GeometryReader { geo in
                let usable = geo.size.width - handleWidth
                let range = item.clipRange ?? ClipRange(start: 0, end: duration)

                ZStack(alignment: .leading) {
                    // Full track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: trackHeight)

                    // Selected region highlight
                    let startX = usable * CGFloat(range.start / max(duration, 1))
                    let endX = usable * CGFloat(range.end / max(duration, 1))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(ClipTheme.accent.opacity(0.25))
                        .frame(width: max(endX - startX, 2), height: trackHeight)
                        .offset(x: startX + handleWidth / 2)

                    // Start handle
                    ClipHandle(color: ClipTheme.accent)
                        .frame(width: handleWidth, height: trackHeight + 8)
                        .offset(x: startX)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let fraction = max(0, min(value.location.x / usable, 1))
                                    let newStart = fraction * duration
                                    var r = item.clipRange ?? ClipRange(start: 0, end: duration)
                                    r.start = min(newStart, r.end - 1)
                                    item.clipRange = r
                                }
                        )

                    // End handle
                    ClipHandle(color: ClipTheme.rosewood)
                        .frame(width: handleWidth, height: trackHeight + 8)
                        .offset(x: endX)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let fraction = max(0, min(value.location.x / usable, 1))
                                    let newEnd = fraction * duration
                                    var r = item.clipRange ?? ClipRange(start: 0, end: duration)
                                    r.end = max(newEnd, r.start + 1)
                                    item.clipRange = r
                                }
                        )
                }
            }
            .frame(height: trackHeight + 8)

            // Time labels and manual inputs
            let range = item.clipRange ?? ClipRange(start: 0, end: duration)

            HStack {
                // Start time
                TimeInput(label: "Start", seconds: range.start, duration: duration) { newVal in
                    var r = item.clipRange ?? ClipRange(start: 0, end: duration)
                    r.start = min(newVal, r.end - 1)
                    item.clipRange = r
                }

                Spacer()

                // Clip duration
                VStack(spacing: 1) {
                    Text("Duration")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(ClipRange.formatTime(range.duration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // End time
                TimeInput(label: "End", seconds: range.end, duration: duration) { newVal in
                    var r = item.clipRange ?? ClipRange(start: 0, end: duration)
                    r.end = max(newVal, r.start + 1)
                    item.clipRange = r
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ClipHandle: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
    }
}

private struct TimeInput: View {
    let label: String
    let seconds: Double
    let duration: Double
    let onChange: (Double) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextField("0:00", text: $text)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .focused($isFocused)
                .onAppear { text = ClipRange.formatTime(seconds) }
                .onChange(of: seconds) { text = ClipRange.formatTime(seconds) }
                .onChange(of: isFocused) {
                    if !isFocused { commitText() }
                }
                .onSubmit { commitText() }
        }
    }

    private func commitText() {
        if let parsed = parseTime(text) {
            let clamped = max(0, min(parsed, duration))
            onChange(clamped)
        }
        text = ClipRange.formatTime(seconds)
    }

    /// Parse "1:23", "1:23:45", or raw seconds "90"
    private func parseTime(_ str: String) -> Double? {
        let parts = str.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 1: return parts[0]
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }
}
