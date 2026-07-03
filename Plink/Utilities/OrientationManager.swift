import SwiftUI
import UIKit

// MARK: - Orientation Manager
/// Управление ориентацией устройства.
/// Позволяет принудительно повернуть экран в ландшафт/портрет.
final class OrientationManager {
    static let shared = OrientationManager()
    private init() {}

    /// Принудительно повернуть в ландшафт.
    func forceLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        // macOS Catalyst / симулятор: через requestGeometryUpdate
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }

        // Fallback: старый API (для старых iOS)
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    /// Принудительно повернуть в портрет.
    func forcePortrait() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }

        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    /// Текущая ориентация портретная?
    var isPortrait: Bool {
        UIDevice.current.orientation.isPortrait || // когда UIDevice даёт корректное значение
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation.isPortrait ?? true &&
         // Если UIDevice.unknown (лежит на столе) — проверяем window
         (UIDevice.current.orientation == .unknown ||
          UIDevice.current.orientation == .faceUp ||
          UIDevice.current.orientation == .faceDown))
    }
}
