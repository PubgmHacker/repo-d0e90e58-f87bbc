// Plink/Playback/PlaybackCoordinator.swift
// Single owner of player lifecycle (runbook §6, §21 + Brain Review P0-8)
//
// Brain P0-8 fix: coordinator now chooses between NativePlayerController
// (for .hls/.mp4/.external) and EmbeddedPlaybackController (for .youtube).
// The two controllers implement the same PlaybackControlling protocol, so
// OrderedSyncController is agnostic to which one is active.
//
// Per §21: 'PlaybackController не отправляет WebSocket сообщения' —
// the coordinator never talks to RealtimeClient.
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
public final class PlaybackCoordinator: AnyObject {
    /// Current active controller — either NativePlayerController or
    /// EmbeddedPlaybackController depending on source type.
    public private(set) var currentController: PlaybackControlling?

    public var position: TimeInterval { currentController?.position ?? 0 }
    public var duration: TimeInterval { currentController?.duration ?? 0 }
    public var isPlaying: Bool { currentController?.isPlaying ?? false }
    public var isBuffering: Bool { currentController?.isBuffering ?? false }
    public var capabilities: PlaybackCapabilities {
        currentController?.capabilities ?? .unknown
    }

    public private(set) var currentSource: PlaybackSource?
    public private(set) var isPreparing: Bool = false
    public private(set) var lastError: String?

    /// Native AVPlayer (nil for embedded YouTube source).
    public var nativePlayer: AVPlayer? {
        (currentController as? NativePlayerController)?.player
    }

    /// Embedded view (nil for native HLS/MP4 source).
    /// Returns the embedded view for YouTube OR Rutube controllers.
    public var embeddedView: UIView? {
        if let youtube = currentController as? EmbeddedPlaybackController {
            return youtube.embeddedView
        }
        if let rutube = currentController as? RutubePlaybackController {
            return rutube.embeddedView
        }
        return nil
    }

    public init() {}

    // P1-36: prepare now throws — caller can catch and decide not to connect
    public func prepare(_ source: PlaybackSource) async throws {
        isPreparing = true
        lastError = nil
        // Teardown any previous controller
        if let prev = currentController {
            if let native = prev as? NativePlayerController { native.teardown() }
            if let embedded = prev as? EmbeddedPlaybackController { embedded.teardown() }
            if let rutube = prev as? RutubePlaybackController { rutube.teardown() }
        }
        currentController = nil

        do {
            let controller: PlaybackControlling
            switch source {
            case .hls, .mp4, .external:
                let native = NativePlayerController()
                try await native.prepare(source)
                controller = native
            case .youtube:
                let embedded = EmbeddedPlaybackController()
                try await embedded.prepare(source)
                controller = embedded
            case .rutube:
                let rutube = RutubePlaybackController()
                try await rutube.prepare(source)
                controller = rutube
            }
            currentController = controller
            currentSource = source
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isPreparing = false
            throw error
        }
        isPreparing = false
    }

    public func teardown() {
        if let native = currentController as? NativePlayerController { native.teardown() }
        if let embedded = currentController as? EmbeddedPlaybackController { embedded.teardown() }
        if let rutube = currentController as? RutubePlaybackController { rutube.teardown() }
        currentController = nil
        currentSource = nil
        lastError = nil
    }

    /// Returns the AVPlayerViewController for PiP / fullscreen presentation.
    /// Returns nil for embedded YouTube source (no AVPlayer).
    public func makePlayerViewController() -> AVPlayerViewController? {
        guard let native = currentController as? NativePlayerController else { return nil }
        let vc = AVPlayerViewController()
        vc.player = native.player
        vc.allowsPictureInPicturePlayback = true
        vc.allowsVideoFrameAnalysis = false
        return vc
    }
}
