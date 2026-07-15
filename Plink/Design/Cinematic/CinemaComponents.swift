// Plink/Design/Cinematic/CinemaComponents.swift
//
// Shared design primitives that complete the Cinema2026 design system.
// These were referenced from Home / Profile / Friends / Admin / Settings
// but had no definition — defined here so the whole app compiles.

import SwiftUI

// MARK: - glassCard modifier
//
// Frosted-glass surface used across cards, panels and sheets.
// Renders a translucent white overlay with a hairline border and
// soft shadow — tuned to sit on top of Cinema2026.background.

extension View {
    /// Frosted-glass card surface.
    /// - Parameters:
    ///   - cornerRadius: Corner radius in points.
    ///   - opacity: Background white opacity (0.0 – 1.0). Default 0.05.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16, opacity: Double = 0.05) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    /// Soft neon glow shadow (formerly in Color+Theme.swift).
    func neonGlow(color: Color = Cinema2026.accent, radius: CGFloat = 14, y: CGFloat = 4) -> some View {
        self.shadow(color: color.opacity(0.45), radius: radius, x: 0, y: y)
    }

    /// Chat text shadow for readability over video (formerly in Color+Theme.swift).
    func chatTextShadow() -> some View {
        self.shadow(color: .black.opacity(0.9), radius: 2.5, x: 0, y: 1)
    }
}

// MARK: - PremiumButtonStyle
//
// Pressable button style used for primary CTAs across the app.
// Supports an optional `glowColor` for accent-specific glow.

struct PremiumButtonStyle: ButtonStyle {
    var glowColor: Color = Cinema2026.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [glowColor, glowColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: glowColor.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 6 : 12,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Color hex initializer
//
// Formerly in Color+Theme.swift. Used by AvatarView and others.

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}


// MARK: - LivingHomeStateOverlay (moved from deleted PlinkLivingHome.swift)
@available(iOS 17.0, *)
struct LivingHomeStateOverlay: View {
    let isLoading: Bool
    var body: some View {
        if isLoading {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Cinema2026.surface.opacity(0.4))
                    .frame(height: 280)
                    .padding(.horizontal, 14)
                ForEach(0..<2, id: \.self) { _ in
                    HStack {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Cinema2026.surface.opacity(0.3))
                                .frame(width: 140, height: 80)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityLabel("Загрузка ленты")
        }
    }
}

// MARK: - CinematicPrimaryButtonStyle (used by PlinkPlusPaywall)
struct CinematicPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(colors: [Cinema2026.accent, Cinema2026.accent.opacity(0.8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - CinemaRadius (used by PlinkPlusPaywall)
enum CinemaRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let extraLarge: CGFloat = 28
}

// MARK: - PosterImage (used by CompactRoomRail)
struct PosterImage: View {
    let url: String?
    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Cinema2026.surface)
        }
    }
}

// MARK: - adminStroke + premiumStroke (used by AvatarView's RingModifier)
extension View {
    func adminStroke(lineWidth: CGFloat = 2) -> some View {
        self.overlay(Circle().stroke(Cinema2026.amber, lineWidth: lineWidth))
    }
    func premiumStroke(lineWidth: CGFloat = 2) -> some View {
        self.overlay(Circle().stroke(Cinema2026.accent, lineWidth: lineWidth))
    }
}

// MARK: - PulsingDot, LiveBadge, dismissKeyboardOnTap, shimmerGradientText, View.if
struct PulsingDot: View {
    let color: Color
    @State private var pulse = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.3 : 1.0)
            .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 3) { PulsingDot(color: .white); Text("LIVE").font(.system(size: 9, weight: .black)) }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Cinema2026.danger, in: Capsule()).foregroundStyle(.white)
    }
}

extension View {
    @ViewBuilder func ifTransform<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}

extension Text {
    func adminShimmerText() -> some View { self.foregroundStyle(Cinema2026.amber).shadow(color: Cinema2026.amber.opacity(0.4), radius: 4) }
}

extension View {
    func shimmerGradientText(colors: [Color] = [Cinema2026.accent, Cinema2026.amber]) -> some View {
        self.foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 4)
    }
}

// MARK: - ConditionalBreathing, GlassButtonStyle, RaveTextFieldStyle, ConditionalGlow
struct ConditionalBreathing: ViewModifier {
    let isActive: Bool; let maxScale: CGFloat; let period: Double
    @State private var breathing = false
    func body(content: Content) -> some View {
        content.scaleEffect(isActive && breathing ? maxScale : 1.0)
            .onAppear { guard isActive else { return }; withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { breathing = true } }
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Cinema2026.text)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RaveTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.font(.system(size: 16)).foregroundStyle(Cinema2026.text)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Cinema2026.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Cinema2026.divider, lineWidth: 0.5))
    }
}

struct ConditionalGlow: ViewModifier {
    let isActive: Bool; let color: Color
    let minRadius: CGFloat; let maxRadius: CGFloat
    let minOpacity: Double; let maxOpacity: Double; let period: Double
    @State private var pulse = false
    func body(content: Content) -> some View {
        content.shadow(color: isActive ? color.opacity(pulse ? maxOpacity : minOpacity) : .clear,
                       radius: isActive ? (pulse ? maxRadius : minRadius) : 0)
            .onAppear { guard isActive else { return }; withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - premiumGlass + glowPulse + telegramGlass
extension View {
    @ViewBuilder func premiumGlass(cornerRadius: CGFloat = 16, opacity: Double = 0.06, ringColor: LinearGradient = Cinema2026.timeline, glow: Bool = false) -> some View {
        self.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(opacity)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(ringColor, lineWidth: glow ? 1.5 : 0.5))
            .shadow(color: glow ? Cinema2026.accent.opacity(0.2) : Color.black.opacity(0.15), radius: glow ? 12 : 6, x: 0, y: glow ? 4 : 2)
    }

    @ViewBuilder func glowPulse(color: Color = Cinema2026.accent, minRadius: CGFloat = 8, maxRadius: CGFloat = 16, minOpacity: Double = 0.2, maxOpacity: Double = 0.5, period: Double = 2.0, radius: CGFloat? = nil, duration: Double? = nil) -> some View {
        self.modifier(ConditionalGlow(isActive: true, color: color, minRadius: radius ?? minRadius, maxRadius: radius ?? maxRadius, minOpacity: minOpacity, maxOpacity: maxOpacity, period: duration ?? period))
    }

    @ViewBuilder func telegramGlass(cornerRadius: CGFloat = 16, opacity: Double = 0.06, borderColor: Color = Color.white.opacity(0.08)) -> some View {
        self.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(opacity)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(borderColor, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
    }
}

// MARK: - LivingHomeStateOverlay

// MARK: - EmojiPickerGrid (used by DMChatView)
struct EmojiPickerGrid: View {
    @Binding var chatText: String
    private let columns = Array(repeating: GridItem(.flexible()), count: 6)
    private let emojis: [String] = ["😀","😂","😍","🥰","😘","🤗","🤔","🤩","🥳","😭","😱","🤯","👍","👎","👏","🙌","🤝","💪","❤️","🔥","✨","🎉","💯","⚡","🌟","💎","👑","🚀","🌈","🎬"]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
                Button { chatText += emoji; HapticManager.impact(.light) } label: {
                    Text(emoji).font(.system(size: 28)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Emoji \(emoji)")
            }
        }.padding(12).background(Cinema2026.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - V4AIState (used by WatchRoomModel + RoomAIAssistantBanner)
enum V4AIState: String, Sendable {
    case idle, listening, thinking, speaking, moderating, offline, failed
}

// MARK: - Rave Color Aliases (for PaywallView, ProfileView compatibility)
// These map old rave* names to Cinema2026 equivalents.

extension Color {
    static var ravePrimary: Color { Cinema2026.accent }
    static var raveSecondary: Color { Cinema2026.accent }
    static var raveAccent: Color { Cinema2026.accent }
    static var raveBackground: Color { Cinema2026.background }
    static var raveCard: Color { Cinema2026.surface }
    static var raveSurface: Color { Cinema2026.surface }
    static var raveRaised: Color { Cinema2026.raised }
    static var raveDivider: Color { Cinema2026.divider }
    static var raveTextPrimary: Color { Cinema2026.text }
    static var raveTextSecondary: Color { Cinema2026.secondary }
    static var raveTextTertiary: Color { Cinema2026.secondary }
    static var raveMuted: Color { Cinema2026.secondary }
    static var raveDanger: Color { Cinema2026.danger }
    static var raveWarning: Color { Cinema2026.amber }
    static var raveGreen: Color { Color(red: 0.15, green: 0.85, blue: 0.64) }
    static var raveCyan: Color { Cinema2026.accent }
    static var raveCoral: Color { Color(red: 1.0, green: 0.42, blue: 0.42) }
    static var raveGradient: LinearGradient {
        LinearGradient(colors: [Cinema2026.accent, Color(red: 0.15, green: 0.85, blue: 0.64)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Bio Color Aliases (for ProfileView, RaveCloneApp compatibility)
extension Color {
    static var bioCyan: Color { Cinema2026.accent }
    static var bioEmerald: Color { Color(red: 0.15, green: 0.85, blue: 0.64) }
    static var bioTeal: Color { Color(red: 0.05, green: 0.71, blue: 0.79) }
    static var bioAmber: Color { Cinema2026.amber }
    static var bioCoral: Color { Color(red: 1.0, green: 0.42, blue: 0.42) }
    static var bioRose: Color { Color(red: 1.0, green: 0.56, blue: 0.67) }
    static var bioObsidian: Color { Cinema2026.background }
    static var bioNeonRing: LinearGradient {
        LinearGradient(colors: [Color.bioCyan.opacity(0.5), Color.bioEmerald.opacity(0.25)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - FeatureFlags stub (for PresenceBar, RaveCloneApp)
