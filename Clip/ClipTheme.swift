import SwiftUI

/// Clip app color palette — calmer tones derived from the brand palette.
/// Each color provides light and dark mode variants tuned for accessibility (WCAG AA contrast).
enum ClipTheme {
    // MARK: - Brand palette (reference)
    // ~Dusk Blue #355070
    // ~Dusty Lavender #6d597a
    // ~Rosewood #b56576
    // ~Light Coral #e56b6f
    // ~Light Bronze #eaac8b

    // MARK: - Semantic colors

    /// Primary accent — Dusk Blue. Used for buttons, selection, active states.
    static let accent = Color("ClipAccent")

    /// Secondary accent — Dusty Lavender. Used for platform badges, secondary highlights.
    static let lavender = Color("ClipLavender")

    /// Warm emphasis — Rosewood. Used for compression, warnings that need attention.
    static let rosewood = Color("ClipRosewood")

    /// Soft alert — Light Coral. Used for errors, failed states.
    static let coral = Color("ClipCoral")

    /// Warm neutral — Light Bronze. Used for subtle highlights, progress, warm accents.
    static let bronze = Color("ClipBronze")

    /// Success indicator — muted teal-green that harmonizes with the palette.
    static let success = Color("ClipSuccess")
}

/// Custom prominent button style that doesn't vanish when the window is occluded.
/// Replaces `.borderedProminent` which has a known macOS SwiftUI rendering bug.
struct ClipProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled
                          ? (configuration.isPressed ? ClipTheme.accent.opacity(0.7) : ClipTheme.accent)
                          : ClipTheme.accent.opacity(0.35))
            )
            .contentShape(Rectangle())
    }
}
