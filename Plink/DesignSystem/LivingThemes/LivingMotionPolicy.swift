// Plink/DesignSystem/LivingThemes/LivingMotionPolicy.swift — GPT-5.6 §5
import SwiftUI
import Combine

@MainActor
@Observable
final class LivingMotionPolicy {
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var thermal = ProcessInfo.processInfo.thermalState
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.thermal = ProcessInfo.processInfo.thermalState }
            .store(in: &cancellables)
    }

    func allowsMotion(reduceMotion: Bool, scenePhase: ScenePhase) -> Bool {
        guard !reduceMotion, scenePhase == .active, !lowPower else { return false }
        return thermal != .serious && thermal != .critical
    }
}
