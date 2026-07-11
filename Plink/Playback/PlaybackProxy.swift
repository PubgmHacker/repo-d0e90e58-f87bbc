// Plink/Playback/PlaybackProxy.swift
// Stable proxy for OrderedSyncController (Brain Review 5 P0-29)
//
// Problem: OrderedSyncController was created with a dummy NativePlayerController
// at init time (coordinator.currentController was nil). The real controller
// created by coordinator.prepare() was never connected to syncController.
//
// Solution: PlaybackProxy is a stable PlaybackControlling that forwards all
// calls to a weak `target`. WatchRoomModel creates the proxy ONCE, passes it
// to OrderedSyncController, and after coordinator.prepare() sets
// playbackProxy.target = coordinator.currentController.
//
// Now authoritative snapshots and live states are applied to the REAL player
// visible in UI, not a hidden dummy.

import Foundation
import Observation

@MainActor
@Observable
public final class PlaybackProxy: PlaybackControlling {
    public weak var target: PlaybackControlling?

    public init(target: PlaybackControlling? = nil) {
        self.target = target
    }

    public var position: TimeInterval { target?.position ?? 0 }
    public var duration: TimeInterval { target?.duration ?? 0 }
    public var isPlaying: Bool { target?.isPlaying ?? false }
    public var isBuffering: Bool { target?.isBuffering ?? false }
    public var capabilities: PlaybackCapabilities { target?.capabilities ?? .unknown }

    public func prepare(_ source: PlaybackSource) async throws {
        guard let target else {
            throw ProviderError.loadingFailed("PlaybackProxy has no target")
        }
        try await target.prepare(source)
    }

    public func play() async {
        await target?.play()
    }

    public func pause() {
        target?.pause()
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard let target else { return .applied }
        return await target.seek(to: seconds, precise: precise)
    }

    public func setRate(_ rate: Float) {
        target?.setRate(rate)
    }
}
