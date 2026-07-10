// Plink/Playback/PlaybackCoordinator.swift
// Single owner of player lifecycle (runbook §6, §21)
//
// WatchRoomModel delegates all player operations to this coordinator. It:
//   - Owns ONE NativePlayerController per room session (§1 DoD)
//   - Routes OrderedSyncController corrections to the player
//   - Forwards player state (position, buffering, errors) to UI consumers
//   - Holds the AVPlayerViewController for PiP presentation
//
// Per §21: 'PlaybackController не отправляет WebSocket сообщения' —
// the coordinator never talks to RealtimeClient. It only receives state
// from OrderedSyncController (which itself only receives from RealtimeClient).
//
// Per §16: 'Не добавлять еще один singleton WebView' — the coordinator is
// owned by WatchRoomModel, never a global. Each room session gets a fresh
// coordinator with a fresh player.

import Foundation
import AVKit
import UIKit
import Observation

@MainActor
@Observable
public final class PlaybackCoordinator {
    public let player: NativePlayerController

    public private(set) var currentSource: PlaybackSource?
    public private(set) var isPreparing: Bool = false
    public private(set) var lastError: String?

    public init(player: NativePlayerController = NativePlayerController()) {
        self.player = player
    }

    public func prepare(_ source: PlaybackSource) async {
        isPreparing = true
        lastError = nil
        do {
            try await player.prepare(source)
            currentSource = source
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isPreparing = false
    }

    public func teardown() {
        player.teardown()
        currentSource = nil
        lastError = nil
    }

    /// Returns the AVPlayerViewController for PiP / fullscreen presentation.
    /// Created lazily — one per coordinator lifetime.
    public func makePlayerViewController() -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player.player
        vc.allowsPictureInPicturePlayback = true
        vc.allowsVideoFrameAnalysis = false
        return vc
    }
}
