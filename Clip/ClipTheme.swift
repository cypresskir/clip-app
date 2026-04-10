import SwiftUI

/// Clip color palette — Tahoe system colors from the macOS 26 design kit.
/// Each color provides light and dark mode variants via asset catalog.
enum ClipTheme {
    // MARK: - Tahoe system accent colors

    /// Blue #0088FF / #0091FF — buttons, selection, active states, progress.
    static let accent = Color("ClipAccent")

    /// Purple #CB30E0 / #DB34F2 — Instagram badge, secondary highlights.
    static let lavender = Color("ClipLavender")

    /// Pink #FF2D55 / #FF375F — compression progress, clip end handle.
    static let rosewood = Color("ClipRosewood")

    /// Red #FF383C / #FF4245 — errors, failed states, YouTube badge.
    static let coral = Color("ClipCoral")

    /// Orange #FF8D28 / #FF9230 — retry, warm accents.
    static let bronze = Color("ClipBronze")

    /// Green #34C759 / #30D158 — complete states.
    static let success = Color("ClipSuccess")

    // MARK: - Tahoe fill colors (opaque system fills)

    /// Primary fill: 10% black (light) / 10% white (dark)
    static let fillPrimary = Color.primary.opacity(0.10)

    /// Secondary fill: 8% black (light) / 8% white (dark)
    static let fillSecondary = Color.primary.opacity(0.08)

    // MARK: - Tahoe Glass constants

    /// Standard corner radius for glass cards
    static let cardRadius: CGFloat = 16
    /// Corner radius for smaller elements (buttons, tags)
    static let smallRadius: CGFloat = 10
    /// Corner radius for pill-shaped elements
    static let pillRadius: CGFloat = 100
}

// MARK: - Glass Card Modifier

/// Applies a Liquid Glass–inspired card style: white surface with subtle border.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = ClipTheme.cardRadius
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = ClipTheme.cardRadius,
        padding: CGFloat = 0
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Button Styles

/// Tahoe-style prominent button: pill shape, vibrant tinted fill, white text.
struct ClipProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.5))
            .padding(.vertical, 8)
            .padding(.horizontal, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled
                          ? (configuration.isPressed ? ClipTheme.accent.opacity(0.65) : ClipTheme.accent)
                          : ClipTheme.accent.opacity(0.45))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(isEnabled ? 0.2 : 0.08), lineWidth: 0.5)
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Glass Progress Bar

/// Tahoe-style progress bar: pill-shaped capsule with 5% black track and vibrant fill.
struct GlassProgressBar: View {
    var value: Double
    var tint: Color = ClipTheme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.05))

                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(geo.size.height, geo.size.width * CGFloat(min(max(value, 0), 1))))
                    .animation(.easeOut(duration: 0.3), value: value)
            }
        }
        .frame(height: height)
    }
}

/// Tahoe-style bordered button: pill shape, white surface.
struct ClipBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
