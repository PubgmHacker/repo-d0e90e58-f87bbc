// Plink/AppShell/AppSection.swift — GPT-5.6 SOL Recovery §8.8
//
// Single canonical tab model: home, discover, create, friends, profile.
// AI becomes contextual (not a tab). Settings lives under Profile.
// Rooms becomes Discover (broader scope).

import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case discover
    case create
    case friends
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Главная"
        case .discover: "Обзор"
        case .create: "Создать"
        case .friends: "Друзья"
        case .profile: "Профиль"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .discover: "safari.fill"
        case .create: "plus"
        case .friends: "person.2.fill"
        case .profile: "person.crop.circle"
        }
    }
}
