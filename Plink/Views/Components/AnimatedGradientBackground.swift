import SwiftUI

// MARK: - AnimatedGradientBackground (deprecated alias → BioluminescentBackground)
//
// 🔧 FIX N1+N2: Was returning Color.clear, which meant 20 screens (sheets/modals
// that don't sit on top of the root BioluminescentBackground) rendered with no
// background at all — just the default UIWindow color. The orbColors and
// hasActiveRooms parameters were silently dropped (5+ call sites passed specific
// palettes that were ignored).
//
// Now forwards to BioluminescentBackground so all 20 screens get the proper
// cyan/teal/emerald animated background. The legacy parameters are accepted
// for source compatibility but ignored (BioluminescentBackground has its own
// palette that's strictly controlled).
struct AnimatedGradientBackground: View {
    var orbColors: [Color] = []
    var hasActiveRooms: Bool = true

    var body: some View {
        // Forward to BioluminescentBackground — ignores legacy orbColors param.
        // hasActiveRooms modulates energy: active rooms = brighter, empty = dimmer.
        // 🔧 PACK v5: energy bumped to 1.0/0.7 (was 0.8/0.55) for full vivid bg.
        BioluminescentBackground(
            energy: hasActiveRooms ? 1.0 : 0.7,
            dimming: 0
        )
    }
}

// MARK: - Glass Card Modifier (legacy alias → premiumGlass)
//
// Сохраняет совместимость со старыми вызовами .glassCard().
// Делегирует на премиальное стекло (cyan/emerald обводка).
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var opacity: Double = 0.04

    func body(content: Content) -> some View {
        content.premiumGlass(cornerRadius: cornerRadius, opacity: opacity)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, opacity: Double = 0.04) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Premium Button Style (legacy → BioluminescentButtonStyle)
/// Делегирует на единый стиль кнопок с биолюминесцентным свечением.
struct PremiumButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Color.raveGradient
    var glowColor: Color = .bioCyan

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .shadow(
                color: glowColor.opacity(configuration.isPressed ? 0.5 : 0.2),
                radius: configuration.isPressed ? 18 : 10,
                y: 0
            )
    }
}

