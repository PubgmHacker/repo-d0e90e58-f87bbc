// Plink/Playback/PlayerViewControllerRepresentable.swift
// SwiftUI bridge (runbook §6 + Brain Review P0-8)
//
// Brain P0-8 fix: supports BOTH paths:
//   - Native HLS/MP4 → AVPlayerViewController (PiP + AirPlay)
//   - Embedded YouTube → WKWebView from EmbeddedPlaybackController
//
// The underlying AVPlayer instance is owned by PlaybackCoordinator —
// this view does NOT create its own player (§1 DoD: 'Background/foreground,
// rotation и fullscreen не создают второй player').

import SwiftUI
import AVKit

public struct PlayerSurfaceView: View {
    public let coordinator: PlaybackCoordinator

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            if let vc = coordinator.makePlayerViewController() {
                PlayerViewControllerRepresentable(controller: vc)
            } else if let embedded = coordinator.embeddedView {
                EmbeddedViewRepresentable(view: embedded)
            } else if let error = coordinator.lastError {
                // Media prepare failed (e.g. YouTube timeout) — show error
                // overlay so the user knows why the player is blank.
                // Chat + participants + reactions still work over WebSocket.
                Color.black
                    .overlay(
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.yellow)
                            Text("Не удалось загрузить видео")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Text("Чат и участники работают")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    )
            } else {
                Color.black
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
        .background(Color.black)
    }
}

public struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    public let controller: AVPlayerViewController

    public init(controller: AVPlayerViewController) {
        self.controller = controller
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        controller
    }

    public func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Keep AVPlayer reference in sync if coordinator rebuilt it
        if vc.player !== coordinator_player(vc) {
            // vc.player is set by the coordinator when it created the VC.
            // Nothing to do here — coordinator owns the AVPlayer.
        }
    }

    private func coordinator_player(_ vc: AVPlayerViewController) -> AVPlayer? {
        vc.player
    }
}

/// Wraps a UIView (WKWebView for embedded YouTube) for SwiftUI.
public struct EmbeddedViewRepresentable: UIViewRepresentable {
    public let view: UIView

    public init(view: UIView) {
        self.view = view
    }

    public func makeUIView(context: Context) -> UIView {
        view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // WKWebView is managed by EmbeddedPlaybackController
    }
}
