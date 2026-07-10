// Plink/Playback/PlayerViewControllerRepresentable.swift
// SwiftUI bridge for AVPlayerViewController (runbook §6)
//
// Wraps AVPlayerViewController for use in WatchRoomScreen. Supports PiP and
// AirPlay natively. The underlying AVPlayer instance is owned by
// PlaybackCoordinator — this view does NOT create its own player (§1 DoD:
// 'Background/foreground, rotation и fullscreen не создают второй player').

import SwiftUI
import AVKit

public struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    public let coordinator: PlaybackCoordinator

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = coordinator.makePlayerViewController()
        return vc
    }

    public func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Keep the AVPlayer reference in sync if the coordinator rebuilt it.
        if vc.player !== coordinator.player.player {
            vc.player = coordinator.player.player
        }
    }
}
