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
        BioluminescentBackground(
            energy: hasActiveRooms ? 0.6 : 0.4,
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

// MARK: - Service Logo Icon (оригинальные, цветные)
struct ServiceLogoIcon: View {
    let service: VideoService
    var size: CGFloat = 32

    var body: some View {
        switch service {
        case .youtube:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(Color(hex: 0xFF0000))
                    .frame(width: size * 1.35, height: size * 0.95)
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            }
        case .vk:
            ZStack {
                Circle().fill(Color(hex: 0x0077FF)).frame(width: size * 1.1, height: size * 1.1)
                Text("VK")
                    .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
        case .rutube:
            ZStack {
                Circle().fill(Color(hex: 0x000000)).frame(width: size * 1.1, height: size * 1.1)
                Text("Ru")
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
        case .netflix:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18)
                    .fill(Color(hex: 0xE50914))
                    .frame(width: size * 1.1, height: size * 1.1)
                Text("N")
                    .font(.system(size: size * 0.6, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        case .disney:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18)
                    .fill(Color(hex: 0x113CCF))
                    .frame(width: size * 1.1, height: size * 1.1)
                Text("D+")
                    .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
        case .browser:
            Image(systemName: "safari.fill")
                .font(.system(size: size))
                .foregroundColor(Color.bioCyan)
        case .customURL:
            Image(systemName: "link")
                .font(.system(size: size))
                .foregroundColor(.bioCyan)
        case .kinopoisk:
            ZStack {
                Circle().fill(Color(hex: 0xFF6600)).frame(width: size * 1.1, height: size * 1.1)
                Text("К")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundColor(.white)
            }
        case .ivi:
            ZStack {
                Circle().fill(Color(hex: 0xE40000)).frame(width: size * 1.1, height: size * 1.1)
                Text("ivi")
                    .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
        case .okko:
            ZStack {
                Circle().fill(Color(hex: 0xFF0033)).frame(width: size * 1.1, height: size * 1.1)
                Text("OK")
                    .font(.system(size: size * 0.38, weight: .heavy))
                    .foregroundColor(.white)
            }
        case .wink:
            ZStack {
                Circle().fill(Color(hex: 0xFF0050)).frame(width: size * 1.1, height: size * 1.1)
                Image(systemName: "eye.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(.white)
            }
        case .start:
            ZStack {
                Circle().fill(Color(hex: 0x7B2CBF)).frame(width: size * 1.1, height: size * 1.1)
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            }
        case .premier:
            ZStack {
                Circle().fill(Color(hex: 0xEF4444)).frame(width: size * 1.1, height: size * 1.1)
                Image(systemName: "crown.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundColor(.white)
            }
        case .smotrim:
            ZStack {
                Circle().fill(Color(hex: 0x00A0AF)).frame(width: size * 1.1, height: size * 1.1)
                Image(systemName: "tv.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundColor(.white)
            }
        case .kion:
            ZStack {
                Circle().fill(Color(hex: 0xF26B1F)).frame(width: size * 1.1, height: size * 1.1)
                Text("K")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
    }
}
