import SwiftUI

// MARK: - Telegram-style DM chat wallpapers

enum PlinkChatWallpaper: String, CaseIterable, Identifiable, Sendable {
    case defaultDark
    case telegramBlue
    case night
    case purpleMist
    case forest
    case sunset
    case graphite
    case aurora

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultDark: return "Тёмный"
        case .telegramBlue: return "Telegram"
        case .night: return "Ночь"
        case .purpleMist: return "Фиолет"
        case .forest: return "Лес"
        case .sunset: return "Закат"
        case .graphite: return "Графит"
        case .aurora: return "Аврора"
        }
    }

    var colors: [Color] {
        switch self {
        case .defaultDark:
            return [Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.07, green: 0.05, blue: 0.12)]
        case .telegramBlue:
            return [Color(red: 0.08, green: 0.14, blue: 0.22),
                    Color(red: 0.10, green: 0.18, blue: 0.28),
                    Color(red: 0.06, green: 0.12, blue: 0.20)]
        case .night:
            return [Color(red: 0.04, green: 0.05, blue: 0.10),
                    Color(red: 0.02, green: 0.03, blue: 0.08)]
        case .purpleMist:
            return [Color(red: 0.12, green: 0.06, blue: 0.18),
                    Color(red: 0.08, green: 0.04, blue: 0.14),
                    Color(red: 0.15, green: 0.08, blue: 0.22)]
        case .forest:
            return [Color(red: 0.05, green: 0.12, blue: 0.09),
                    Color(red: 0.03, green: 0.08, blue: 0.06)]
        case .sunset:
            return [Color(red: 0.18, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.05, blue: 0.14),
                    Color(red: 0.08, green: 0.05, blue: 0.12)]
        case .graphite:
            return [Color(red: 0.12, green: 0.12, blue: 0.13),
                    Color(red: 0.08, green: 0.08, blue: 0.09)]
        case .aurora:
            return [Color(red: 0.04, green: 0.12, blue: 0.16),
                    Color(red: 0.08, green: 0.06, blue: 0.18),
                    Color(red: 0.04, green: 0.10, blue: 0.12)]
        }
    }

    @ViewBuilder
    var background: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Subtle pattern dots like Telegram wallpapers
            Canvas { ctx, size in
                let step: CGFloat = 28
                var y: CGFloat = 12
                while y < size.height {
                    var x: CGFloat = 12
                    while x < size.width {
                        let r = CGRect(x: x, y: y, width: 2.2, height: 2.2)
                        ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.04)))
                        x += step
                    }
                    y += step
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

enum PlinkChatWallpaperPrefs {
    static let storageKey = "plink.chatWallpaperID"

    static var current: PlinkChatWallpaper {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? PlinkChatWallpaper.defaultDark.rawValue
        return PlinkChatWallpaper(rawValue: raw) ?? .defaultDark
    }

    static func set(_ wallpaper: PlinkChatWallpaper) {
        UserDefaults.standard.set(wallpaper.rawValue, forKey: storageKey)
        NotificationCenter.default.post(name: .plinkChatWallpaperChanged, object: wallpaper.rawValue)
    }
}

extension Notification.Name {
    static let plinkChatWallpaperChanged = Notification.Name("plink.chatWallpaperChanged")
}
