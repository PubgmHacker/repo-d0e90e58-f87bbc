// Plink/Extensions/View+TelegramGlass.swift
//
// GPT-5.6 SOL fix: telegramGlass and glowPulse modifiers were in deleted files.
// Recreated here as minimal implementations for back-compat.
// Used by AIAssistantView, AdminPanelView, and other screens.

import SwiftUI

extension View {
    /// Telegram-style frosted glass surface modifier.
    /// Renders a translucent background with subtle blur + hairline border.
    /// - Parameters:
    ///   - cornerRadius: Corner radius in points (default 16).
    ///   - opacity: Background opacity (default 0.06).
    ///   - borderColor: Border color (default white.opacity(0.08)).
    @ViewBuilder
    func telegramGlass(cornerRadius: CGFloat = 16, opacity: Double = 0.06, borderColor: Color = Color.white.opacity(0.08)) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
    }

    /// Pulsing glow effect for accent elements.
    /// Animates shadow opacity + radius in a repeating cycle.
    /// - Parameters:
    ///   - color: Glow color (default Cinema2026.accent).
    ///   - minRadius: Minimum glow radius (default 8).
    ///   - maxRadius: Maximum glow radius (default 16).
    ///   - minOpacity: Minimum opacity (default 0.2).
    ///   - maxOpacity: Maximum opacity (default 0.5).
    ///   - period: Animation duration in seconds (default 2.0).
    ///   - radius: Legacy single radius parameter (used when minRadius/maxRadius not specified).
    ///   - duration: Legacy single duration parameter (used when period not specified).
    @ViewBuilder
    func glowPulse(
        color: Color = Cinema2026.accent,
        minRadius: CGFloat = 8,
        maxRadius: CGFloat = 16,
        minOpacity: Double = 0.2,
        maxOpacity: Double = 0.5,
        period: Double = 2.0,
        radius: CGFloat? = nil,
        duration: Double? = nil
    ) -> some View {
        let actualMinRadius = radius ?? minRadius
        let actualMaxRadius = radius ?? maxRadius
        let actualPeriod = duration ?? period
        modifier(GlowPulseModifier(
            color: color,
            minRadius: actualMinRadius,
            maxRadius: actualMaxRadius,
            minOpacity: minOpacity,
            maxOpacity: maxOpacity,
            period: actualPeriod
        ))
    }

    /// Premium glass surface modifier — frosted glass with optional neon ring + glow.
    /// Used by RoomCardView for room cards.
    /// - Parameters:
    ///   - cornerRadius: Corner radius in points.
    ///   - opacity: Background white opacity.
    ///   - ringColor: Linear gradient for the border ring (active rooms glow).
    ///   - glow: Whether to add a glow shadow (active rooms).
    @ViewBuilder
    func premiumGlass(
        cornerRadius: CGFloat = 16,
        opacity: Double = 0.06,
        ringColor: LinearGradient = Cinema2026.timeline,
        glow: Bool = false
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ringColor, lineWidth: glow ? 1.5 : 0.5)
            )
            .shadow(
                color: glow ? Cinema2026.accent.opacity(0.2) : Color.black.opacity(0.15),
                radius: glow ? 12 : 6,
                x: 0,
                y: glow ? 4 : 2
            )
    }
}

/// Modifier that animates a pulsing glow shadow.
private struct GlowPulseModifier: ViewModifier {
    let color: Color
    let minRadius: CGFloat
    let maxRadius: CGFloat
    let minOpacity: Double
    let maxOpacity: Double
    let period: Double
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: color.opacity(pulse ? maxOpacity : minOpacity),
                radius: pulse ? maxRadius : minRadius
            )
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
