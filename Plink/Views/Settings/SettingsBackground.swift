// Plink/Views/Settings/SettingsBackground.swift
//
// GPT-5.6 SOL fix: SettingsBackground was in a deleted file.
// Recreated as a minimal animated background for SettingsView.

import SwiftUI

/// Animated grayscale background for Settings screen.
/// Uses subtle gradient + slow-moving orbs (grayscale only, no color).
struct SettingsBackground: View {
    let energy: Double  // 0...1, controls animation intensity

    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Cinema2026.background

            if !reduceMotion {
                // Grayscale orb 1
                Circle()
                    .fill(Color.white.opacity(0.04 * energy))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .offset(x: phase ? 80 : -60, y: phase ? -40 : 60)

                // Grayscale orb 2
                Circle()
                    .fill(Color.white.opacity(0.03 * energy))
                    .frame(width: 180, height: 180)
                    .blur(radius: 70)
                    .offset(x: phase ? -70 : 80, y: phase ? 50 : -50)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
