import SwiftUI

// Refined palette — deep, warm dark, NOT cyberpunk neon.
// Inspired by professional streaming apps (Twitch, Discord dark, Apple Music).
// Colors are muted but rich — they glow subtly, not scream.

enum PlinkRave {
    // Base — warm dark, not pure black. Like a dim cinema.
    static let void = Color(hex: 0x0F0D14)        // very dark warm grey-purple
    static let surface = Color(hex: 0x1C1923)      // card background, slightly lighter
    static let raised = Color(hex: 0x2A2533)       // buttons, raised elements

    // Accents — rich, not neon. Like gemstones, not LEDs.
    static let primary = Color(hex: 0x7C5CFF)      // amethyst purple (soft, not magenta)
    static let primaryDim = Color(hex: 0x4A3A8F)   // dimmer purple for tracks
    static let secondary = Color(hex: 0x5EC8F5)    // soft sky blue (not cyan)
    static let accent = Color(hex: 0xE8506B)       // warm coral pink (not hot pink)
    static let gold = Color(hex: 0xE8B647)         // warm gold for host/premium

    // Status — clear but not aggressive
    static let success = Color(hex: 0x3DD68C)      // soft mint green
    static let warning = Color(hex: 0xE8B647)      // same gold
    static let danger = Color(hex: 0xE8506B)       // same coral

    // Text — warm whites, not pure
    static let text = Color(hex: 0xF2EDF7)         // warm white
    static let textSecondary = Color(hex: 0x8E85A0) // muted lavender grey
    static let textTertiary = Color(hex: 0x5A5266)  // very muted

    // Lines
    static let divider = Color(hex: 0x2D2838)

    // Gradients — subtle, not flashy
    static let outgoingBubble = LinearGradient(
        colors: [Color(hex: 0x7C5CFF), Color(hex: 0x5A3FD6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let primaryAction = LinearGradient(
        colors: [Color(hex: 0x7C5CFF), Color(hex: 0x9B7CFF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let timeline = LinearGradient(
        colors: [Color(hex: 0x7C5CFF), Color(hex: 0x5EC8F5)],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Ambient — for background glow
    static let ambientGlow = LinearGradient(
        colors: [Color(hex: 0x7C5CFF).opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension View {
    func plinkGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        shadow(color: color.opacity(0.25), radius: radius)
    }
}
