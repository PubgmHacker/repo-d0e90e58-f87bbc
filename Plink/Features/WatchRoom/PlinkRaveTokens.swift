import SwiftUI

enum PlinkRave {
    static let void = Color(hex: 0x0D001A)
    static let surface = Color(hex: 0x1A0A2E)
    static let raised = Color(hex: 0x271040)
    static let magenta = Color(hex: 0xFF00FF)
    static let cyan = Color(hex: 0x00FFFF)
    static let hotPink = Color(hex: 0xFF1493)
    static let success = Color(hex: 0x39FF14)
    static let warning = Color(hex: 0xFFFF00)
    static let danger = Color(hex: 0xFF0040)
    static let text = Color(hex: 0xF6F0FA)
    static let textSecondary = Color(hex: 0xB9AFC4)
    static let divider = Color(hex: 0x4A315C)

    static let outgoingBubble = LinearGradient(
        colors: [magenta, Color(hex: 0x8B008B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let primaryAction = LinearGradient(
        colors: [magenta, hotPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let timeline = LinearGradient(
        colors: [magenta, hotPink],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension View {
    func plinkGlow(_ color: Color, radius: CGFloat = 12) -> some View {
        shadow(color: color.opacity(0.34), radius: radius)
    }
}
