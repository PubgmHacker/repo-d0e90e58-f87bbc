// Plink/AppShell/AppSection.swift — §4 Final Architecture
//
// Exactly 5 tabs: Главная, Комнаты, ИИ, Друзья, Настройки

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
        case .home: "Главная"
        case .rooms: "Комнаты"
        case .ai: "ИИ"
        case .friends: "Друзья"
        case .settings: "Настройки"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .rooms: "rectangle.stack.badge.play"
        case .ai: "sparkles"
        case .friends: "person.2"
        case .settings: "gearshape"
        }
    }
}
