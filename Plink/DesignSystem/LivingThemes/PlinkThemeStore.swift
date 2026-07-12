// Plink/DesignSystem/LivingThemes/PlinkThemeStore.swift — GPT-5.6 §6
import SwiftUI

@MainActor
@Observable
final class PlinkThemeStore {
    private(set) var appTheme = PlinkThemeCatalog.resolve(nil)
    private(set) var roomTheme: PlinkLivingTheme?

    func selectAppTheme(id: String, hasPremium: Bool) throws {
        let theme = PlinkThemeCatalog.resolve(id)
        guard theme.access == .free || hasPremium else { throw ThemeError.premiumRequired }
        appTheme = theme
    }

    func applyServerRoomTheme(id: String?) {
        roomTheme = PlinkThemeCatalog.resolve(id)
    }

    enum ThemeError: Error { case premiumRequired }
}
