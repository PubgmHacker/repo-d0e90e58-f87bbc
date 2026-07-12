// Plink/Features/WatchRoom/PurpleAmbientBackdrop.swift — PATCH 01: ambient layer
//
// Commit Group 1: static two-source purple haze.
// Commit 7 (PATCH 06 — Living background) will replace the static palette
// with one sampled from AVPlayerItemVideoOutput for native sources, and
// fall back to this static palette for DRM/WebView sources where sampling
// is forbidden.
//
// This file deliberately does NOT depend on AVFoundation. Commit 7 will
// add the AmbientVideoSampler actor and wire it in here without changing
// the public init signature, so call sites don't need to be touched.

import SwiftUI

struct PurpleAmbientBackdrop: View {
    let state: AmbientState

    init(state: AmbientState = AmbientState()) {
        self.state = state
    }

    var body: some View {
        ZStack {
            Cinema2026.background

            // Magenta haze, top-leading
            RadialGradient(
                colors: [state.primaryColor.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
            .blur(radius: 70)
            .opacity(state.intensity)

            // Cyan haze, bottom-trailing
            RadialGradient(
                colors: [state.secondaryColor.opacity(0.14), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
            .blur(radius: 90)
            .opacity(state.intensity)

            // Bottom vignette so player chrome doesn't vanish into the void
            LinearGradient(
                colors: [.clear, Cinema2026.background.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.4)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Ambient state

struct AmbientState: Equatable, Sendable {
    /// 0...1. Lowered when Low Power Mode is on, when thermal state is .serious,
    /// or when Reduce Transparency is enabled.
    var intensity: Double = 0.55

    /// Sampled palette (Commit 7). Until then, defaults to brand magenta/cyan.
    var primaryColor: Color = Cinema2026.accent
    var secondaryColor: Color = Cinema2026.secondary
}

#if DEBUG
#Preview {
    PurpleAmbientBackdrop(state: AmbientState())
        .background(Cinema2026.background)
}
#endif
