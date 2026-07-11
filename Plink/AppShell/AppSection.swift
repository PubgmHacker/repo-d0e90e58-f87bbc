// Plink/AppShell/AppSection.swift — Navigation sections
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §2: App sections

import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case rooms
    case create
    case friends
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .rooms: return "Комнаты"
        case .create: return "Создать"
        case .friends: return "Друзья"
        case .profile: return "Профиль"
        case .settings: return "Настройки"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .rooms: return "play.rectangle.on.rectangle"
        case .create: return "plus"
        case .friends: return "person.2"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }
}
