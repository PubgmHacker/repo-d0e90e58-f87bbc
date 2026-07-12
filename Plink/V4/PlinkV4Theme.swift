import SwiftUI
import Observation

public struct V4RGBA: Codable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}

public struct V4Theme: Identifiable, Codable, Hashable, Sendable {
    public enum Access: String, Codable, Sendable { case free, premium }
    public let id: String
    public let name: String
    public let access: Access
    public let base: V4RGBA
    public let primary: V4RGBA
    public let secondary: V4RGBA
    public let tertiary: V4RGBA
    public let chatScrim: V4RGBA
}

public enum V4ThemeCatalog {
    public static let defaultID = "electric-blue"

    public static let electricBlue = V4Theme(
        id: "electric-blue", name: "Electric Blue", access: .free,
        base: .init(red: 0.025, green: 0.055, blue: 0.15, alpha: 1),
        primary: .init(red: 0.08, green: 0.35, blue: 0.92, alpha: 1),
        secondary: .init(red: 0.34, green: 0.84, blue: 1, alpha: 1),
        tertiary: .init(red: 0.40, green: 0.22, blue: 0.92, alpha: 1),
        chatScrim: .init(red: 0.018, green: 0.035, blue: 0.09, alpha: 0.52)
    )

    public static let cinemaEmber = V4Theme(
        id: "cinema-ember", name: "Cinema Ember", access: .premium,
        base: .init(red: 0.10, green: 0.025, blue: 0.008, alpha: 1),
        primary: .init(red: 0.78, green: 0.16, blue: 0.025, alpha: 1),
        secondary: .init(red: 1, green: 0.62, blue: 0.12, alpha: 1),
        tertiary: .init(red: 0.96, green: 0.28, blue: 0.08, alpha: 1),
        chatScrim: .init(red: 0.08, green: 0.025, blue: 0.01, alpha: 0.56)
    )

    public static let violetHorizon = V4Theme(
        id: "violet-horizon", name: "Violet Horizon", access: .premium,
        base: .init(red: 0.04, green: 0.02, blue: 0.10, alpha: 1),
        primary: .init(red: 0.30, green: 0.08, blue: 0.82, alpha: 1),
        secondary: .init(red: 0.82, green: 0.20, blue: 0.94, alpha: 1),
        tertiary: .init(red: 0.55, green: 0.30, blue: 1, alpha: 1),
        chatScrim: .init(red: 0.04, green: 0.02, blue: 0.10, alpha: 0.56)
    )

    public static let plinkTeal = V4Theme(
        id: "plink-teal", name: "Plink Teal", access: .premium,
        base: .init(red: 0.018, green: 0.055, blue: 0.06, alpha: 1),
        primary: .init(red: 0.06, green: 0.48, blue: 0.50, alpha: 1),
        secondary: .init(red: 0.22, green: 0.34, blue: 0.90, alpha: 1),
        tertiary: .init(red: 0.55, green: 0.20, blue: 0.68, alpha: 1),
        chatScrim: .init(red: 0.02, green: 0.06, blue: 0.065, alpha: 0.56)
    )

    public static let magentaBloom = V4Theme(
        id: "magenta-bloom", name: "Magenta Bloom", access: .premium,
        base: .init(red: 0.08, green: 0.015, blue: 0.10, alpha: 1),
        primary: .init(red: 0.66, green: 0.03, blue: 0.48, alpha: 1),
        secondary: .init(red: 1, green: 0.20, blue: 0.42, alpha: 1),
        tertiary: .init(red: 0.70, green: 0.20, blue: 0.90, alpha: 1),
        chatScrim: .init(red: 0.08, green: 0.02, blue: 0.10, alpha: 0.56)
    )

    public static let all = [electricBlue, cinemaEmber, violetHorizon, plinkTeal, magentaBloom]
    public static func resolve(_ id: String?) -> V4Theme { all.first { $0.id == id } ?? electricBlue }
}

public enum V4SurfaceKind: Sendable { case home, rooms, ai, friends, profile, roomChat }

@MainActor
@Observable
public final class V4ThemeStore {
    public var appTheme: V4Theme = V4ThemeCatalog.electricBlue
    public var roomTheme: V4Theme = V4ThemeCatalog.electricBlue
    public var hasPremium = false
    public var motionEnabled = true

    public func selectApp(_ id: String) throws {
        let theme = V4ThemeCatalog.resolve(id)
        guard theme.access == .free || hasPremium else { throw ThemeError.premiumRequired }
        appTheme = theme
    }

    public func applyRoomTheme(_ id: String?) { roomTheme = V4ThemeCatalog.resolve(id) }
    public enum ThemeError: Error { case premiumRequired }
}

public enum V4Tokens {
    public static let background = Color(red: 0.025, green: 0.035, blue: 0.04)
    public static let surface = Color(red: 0.105, green: 0.12, blue: 0.13)
    public static let raised = Color(red: 0.15, green: 0.17, blue: 0.18)
    public static let text = Color(red: 0.95, green: 0.965, blue: 0.97)
    public static let secondaryText = Color(red: 0.66, green: 0.70, blue: 0.72)
    public static let accent = Color(red: 0.355, green: 0.690, blue: 0.610)
    public static let warning = Color(red: 0.92, green: 0.68, blue: 0.20)
    public static let danger = Color(red: 0.92, green: 0.24, blue: 0.25)
    public static let horizontal: CGFloat = 19
    public static let sectionGap: CGFloat = 28
    public static let cornerLarge: CGFloat = 29
    public static let cornerMedium: CGFloat = 20
    public static let cornerSmall: CGFloat = 15
    public static let tabHeight: CGFloat = 69
}

public struct V4LivingBackground: View {
    public let theme: V4Theme
    public let surface: V4SurfaceKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    private var intensity: Double {
        switch surface {
        case .home: 1
        case .rooms: 0.82
        case .ai: 0.90
        case .friends: 0.68
        case .profile: 0.52
        case .roomChat: 0.44
        }
    }

    public var body: some View {
        Group {
            if reduceTransparency {
                LinearGradient(colors: [theme.base.color, theme.primary.color.opacity(0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    Canvas(rendersAsynchronously: true) { context, size in
                        draw(context: &context, size: size, date: timeline.date)
                    }
                }
            }
        }
        .overlay {
            LinearGradient(colors: [.clear, Color.black.opacity(surface == .roomChat ? 0.62 : 0.78)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, date: Date) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(theme.base.color))
        let animated = !reduceMotion && scenePhase == .active && ProcessInfo.processInfo.isLowPowerModeEnabled == false
        let t = animated ? date.timeIntervalSinceReferenceDate : 0
        let specs: [(Color, Double, Double, Double)] = [
            (theme.primary.color, 0.13, 0.11, 0.00),
            (theme.secondary.color, 0.11, 0.10, 2.10),
            (theme.tertiary.color, 0.16, 0.08, 4.20)
        ]
        for (index, spec) in specs.enumerated() {
            if surface == .roomChat && index == 2 { continue }
            let diameter = max(size.width, size.height) * 0.92
            let center = CGPoint(
                x: size.width * (index == 0 ? 0.10 : index == 1 ? 0.92 : 0.42) + sin(t * spec.1 + spec.3) * size.width * spec.2,
                y: size.height * (index == 0 ? 0.12 : index == 1 ? 0.54 : 0.96) + cos(t * spec.1 * 0.82 + spec.3) * size.height * spec.2
            )
            let ellipse = CGRect(x: center.x - diameter/2, y: center.y - diameter/2, width: diameter, height: diameter)
            context.drawLayer { layer in
                let opacityBySurface: Double = switch surface {
        case .home: 0.66; case .rooms: 0.60; case .ai: 0.64
        case .friends: 0.54; case .profile: 0.46; case .roomChat: 0.42
        }
        layer.opacity = (opacityBySurface - Double(index) * 0.04) * intensity
                layer.addFilter(.blur(radius: max(38, diameter * 0.09)))
                layer.fill(Path(ellipseIn: ellipse), with: .color(spec.0))
            }
        }
    }
}

public struct V4SurfaceView<Content: View>: View {
    let theme: V4Theme
    let surface: V4SurfaceKind
    @ViewBuilder let content: Content

    public var body: some View {
        ZStack {
            V4LivingBackground(theme: theme, surface: surface).ignoresSafeArea()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
