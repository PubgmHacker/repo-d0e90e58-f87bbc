// Plink/Features/WatchRoom/WatchRoomLayoutState.swift — PATCH 04: stable rotation
//
// GLM-5.2 master implementation patch — Commit Group 2 (PATCH 02 + 04).
//
// Owns layout-variant state for the WatchRoom. Decouples orientation-driven
// layout switches from the rest of the UI state so PlayerStage's underlying
// UIViewRepresentable is NOT recreated when the device rotates.
//
// Critical rule (PATCH 02 spec): all three layouts (portrait / landscape /
// tablet) receive the same PlayerStage owner/model. Never call prepare(),
// recreate AVPlayer, or recreate WKWebView due to orientation.
//
// Identity is preserved by:
//   1. Holding PlayerStage outside the layout switch in WatchRoomScreen's
//      ZStack, so SwiftUI's diff treats it as the same view across rotations.
//   2. Using .id(stable) on PlayerStage — the id never changes with layout.
//   3. Avoiding matchedGeometryEffect across layout boundaries (it forces
//      view-tree rebuilds when geometry snapshots differ).
//
// Animation: 0.4s smooth spring with damping >= 0.9 per PATCH 04 spec.

import SwiftUI

struct WatchRoomLayoutState: Equatable {
    let isLandscape: Bool
    let isTablet: Bool
    let chatDrawerOpen: Bool
    let controlsVisible: Bool
    let isScrubbing: Bool

    static let initial = WatchRoomLayoutState(
        isLandscape: false,
        isTablet: false,
        chatDrawerOpen: true,
        controlsVisible: true,
        isScrubbing: false
    )
}

extension WatchRoomLayoutState {
    /// One-line layout identifier for switch statements. Stable across
    /// orientation jitter — only changes when the canonical layout changes.
    var variant: Variant {
        if isTablet { return .tablet }
        if isLandscape { return .landscape }
        return .portrait
    }

    enum Variant: Equatable, Sendable {
        case portrait, landscape, tablet
    }
}

/// Smooth spring used for all layout transitions in WatchRoom.
/// Damping 0.92, response 0.42 — feels weighted, not bouncy.
extension Animation {
    static let plinkLayout = .smooth(duration: 0.42, extraBounce: 0.04)
    static let plinkControls = .easeOut(duration: 0.22)
    static let plinkDrawer = .smooth(duration: 0.38, extraBounce: 0.06)
}
