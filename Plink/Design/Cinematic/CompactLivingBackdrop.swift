// Plink/Design/Cinematic/CompactLivingBackdrop.swift — §7 Final Unified
//
// Subtle ambient backdrop with accessibility + power gating.

import SwiftUI

struct CompactLivingBackdrop: View {
    let primary: Color
    let secondary: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = false

    var body: some View {
        ZStack {
            Cinema2026.background
            if !reduceTransparency {
                Circle()
                    .fill(primary.opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 68)
                    .offset(x: phase ? 82 : -68, y: phase ? -90 : 44)
                Circle()
                    .fill(secondary.opacity(0.13))
                    .frame(width: 230, height: 230)
                    .blur(radius: 76)
                    .offset(x: phase ? -76 : 90, y: phase ? 110 : -56)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
