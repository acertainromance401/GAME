import SwiftUI

/// Shared visual language for every panel/card in the app: soft rounded corners, a frosted glass fill, a
/// gradient accent-glow border, and a matching drop shadow — replacing the old flat, hard-cornered
/// `Rectangle().stroke(...)` panels (settings, waiting room, confirmation dialogs, HUD banners) with one
/// consistent "premium card" treatment instead of each screen inventing its own.
enum UIStyleKit {
    static let cardCornerRadius: CGFloat = 22
    static let controlCornerRadius: CGFloat = 14
    static let combatControlCornerRadius: CGFloat = 10
    static let chipCornerRadius: CGFloat = 12
}

private struct GlowPanelBackground: ViewModifier {
    let accent: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.42), Color.black.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.6), accent.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
            )
            .clipShape(shape)
            .shadow(color: accent.opacity(0.18), radius: 16, y: 8)
            .shadow(color: .black.opacity(0.5), radius: 22, y: 14)
    }
}

extension View {
    /// Frosted, rounded modal/panel card with an accent-colored glow border. Use for every full overlay
    /// (settings, waiting room, confirmations, HUD banners) so they read as one coherent design system.
    func glowPanel(accent: Color, cornerRadius: CGFloat = UIStyleKit.cardCornerRadius) -> some View {
        modifier(GlowPanelBackground(accent: accent, cornerRadius: cornerRadius))
    }

    /// Rounded "chip" background for selectable rows (style/outfit/language pickers, settings rows) — a
    /// soft gradient fill plus glow shadow when selected, a plain hairline glass fill when not, so the
    /// active choice always reads clearly at a glance without needing a separate checkmark.
    func selectableChip(isSelected: Bool, accent: Color, cornerRadius: CGFloat = UIStyleKit.chipCornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                shape.fill(
                    isSelected
                        ? AnyShapeStyle(accent.opacity(0.35))
                        : AnyShapeStyle(Color.white.opacity(0.055))
                )
            )
            .overlay(shape.stroke(isSelected ? accent.opacity(0.6) : .white.opacity(0.16), lineWidth: isSelected ? 1.6 : 1))
            .clipShape(shape)
            .shadow(color: isSelected ? accent.opacity(0.22) : .clear, radius: 8, y: 3)
    }
}
