// Plink/AppShell/AppSection.swift — Navigation sections
//
// PATCH 26: removed .create (was intercepting tab), added .ai back

import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case rooms
    case ai
    case friends
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .rooms: return "Комнаты"
        case .ai: return "ИИ"
        case .friends: return "Друзья"
        case .settings: return "Настройки"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .rooms: return "play.rectangle.on.rectangle"
        case .ai: return "sparkles"
        case .friends: return "person.2"
        case .settings: return "gearshape"
        }
    }
}
