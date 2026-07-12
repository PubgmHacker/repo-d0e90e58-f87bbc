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
    /// Animates shadow opacity in a 2-second cycle.
    /// - Parameters:
    ///   - color: Glow color (default Cinema2026.accent).
    ///   - radius: Glow radius in points (default 12).
    ///   - duration: Animation duration in seconds (default 2.0).
    @ViewBuilder
    func glowPulse(color: Color = Cinema2026.accent, radius: CGFloat = 12, duration: Double = 2.0) -> some View {
        modifier(GlowPulseModifier(color: color, radius: radius, duration: duration))
    }
}

/// Modifier that animates a pulsing glow shadow.
private struct GlowPulseModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let duration: Double
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: color.opacity(pulse ? 0.6 : 0.2),
                radius: pulse ? radius : radius * 0.5
            )
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
