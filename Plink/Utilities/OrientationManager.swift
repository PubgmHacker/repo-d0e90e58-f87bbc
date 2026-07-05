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
            // 🔧 iOS 16+: заменённый API вместо устаревшего attemptRotationToDeviceOrientation().
            // Просит UIKit пересчитать поддерживаемые ориентации для всех VC в сцене.
            for vc in scene.windows.compactMap({ $0.rootViewController }) {
                vc.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }

        // Fallback: старый API (для старых iOS)
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        if #available(iOS 16.0, *) {
            // уже вызвали setNeedsUpdateOfSupportedInterfaceOrientations выше
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    /// Принудительно повернуть в портрет.
    func forcePortrait() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            // 🔧 iOS 16+: заменённый API вместо устаревшего attemptRotationToDeviceOrientation().
            for vc in scene.windows.compactMap({ $0.rootViewController }) {
                vc.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }

        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        if #available(iOS 16.0, *) {
            // уже вызвали setNeedsUpdateOfSupportedInterfaceOrientations выше
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    /// Текущая ориентация портретная?
    /// 🔧 FIX M9: Added explicit parentheses — `??` has lower precedence than `&&`,
    /// so the old expression parsed as `interfaceOrientation.isPortrait ?? (true && (...))`
    /// which returned true for landscape orientations when UIDevice was .unknown.
    var isPortrait: Bool {
        if UIDevice.current.orientation.isPortrait {
            return true
        }
        // Если UIDevice.unknown (лежит на столе) — проверяем window scene
        if UIDevice.current.orientation == .unknown ||
           UIDevice.current.orientation == .faceUp ||
           UIDevice.current.orientation == .faceDown {
            let windowIsPortrait = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .interfaceOrientation.isPortrait ?? true
            return windowIsPortrait
        }
        return false
    }
}
