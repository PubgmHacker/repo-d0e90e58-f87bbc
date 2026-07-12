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

