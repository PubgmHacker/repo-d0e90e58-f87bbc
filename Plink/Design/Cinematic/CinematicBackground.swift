// Plink/Design/Cinematic/CinematicBackground.swift — Ambient backdrop
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §1: Background

import SwiftUI

struct CinematicBackground: View {
    var body: some View {
        ZStack {
            CinemaColor.background

            // Subtle top glow — barely visible, creates depth
            RadialGradient(
                colors: [CinemaColor.plink.opacity(0.04), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 400
            )

            // Bottom warmth
            RadialGradient(
                colors: [CinemaColor.surface.opacity(0.3), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
