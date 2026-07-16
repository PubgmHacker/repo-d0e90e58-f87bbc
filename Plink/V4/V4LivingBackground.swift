// Plink/V4/V4LivingBackground.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct V4LivingBackground: View {
    let theme: V4Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 3 orbs × 3 independent phases each (offset, scale, rotation) = chaotic
    @State private var p1a = false
    @State private var p1b = false
    @State private var p1c = false
    @State private var p2a = false
    @State private var p2b = false
    @State private var p2c = false
    @State private var p3a = false
    @State private var p3b = false
    @State private var p3c = false

    var body: some View {
        GeometryReader { g in
            let (c0, c1, c2, c3) = theme.colors
            ZStack {
                c0
                blob(c1, g, x: -0.35, y: -0.15, size: 0.85, blur: 36, opacity: 0.52,
                     dxA: 0.44, dyA: 0.30, scaleA: 1.14, rotA: 7,
                     pA: p1a, pB: p1b, pC: p1c)
                blob(c2, g, x:  0.45, y:  0.28, size: 0.68, blur: 34, opacity: 0.45,
                     dxA: -0.39, dyA: -0.21, scaleA: 0.92, rotA: -6,
                     pA: p2a, pB: p2b, pC: p2c)
                blob(c3, g, x:  0.12, y:  0.70, size: 0.82, blur: 34, opacity: 0.45,
                     dxA: 0.10, dyA: -0.30, scaleA: 1.12, rotA: 0,
                     pA: p3a, pB: p3b, pC: p3c)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.10),
                    .init(color: Color.oklch(0.06,0.01,190,alpha:0.10), location: 0.36),
                    .init(color: Color.oklch(0.06,0.01,190,alpha:0.86), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: g.size.width * 1.3, height: g.size.height * 1.3)
            .offset(x: -g.size.width * 0.15, y: -g.size.height * 0.15)
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                // Each orb has 3 independent animations with different durations → chaotic
                // Orb 1: offset 5s, scale 7s, rotation 3s
                withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 5).repeatForever(autoreverses: true)) { p1a = true }
                withAnimation(.timingCurve(0.3, 0, 0.7, 1, duration: 7).repeatForever(autoreverses: true)) { p1b = true }
                withAnimation(.timingCurve(0.5, 0, 0.5, 1, duration: 3).repeatForever(autoreverses: true)) { p1c = true }
                // Orb 2: offset 6s, scale 4s, rotation 8s (staggered start)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 6).repeatForever(autoreverses: true)) { p2a = true }
                    withAnimation(.timingCurve(0.3, 0, 0.7, 1, duration: 4).repeatForever(autoreverses: true)) { p2b = true }
                    withAnimation(.timingCurve(0.5, 0, 0.5, 1, duration: 8).repeatForever(autoreverses: true)) { p2c = true }
                }
                // Orb 3: offset 4s, scale 9s, rotation 5s (staggered start)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 4).repeatForever(autoreverses: true)) { p3a = true }
                    withAnimation(.timingCurve(0.3, 0, 0.7, 1, duration: 9).repeatForever(autoreverses: true)) { p3b = true }
                    withAnimation(.timingCurve(0.5, 0, 0.5, 1, duration: 5).repeatForever(autoreverses: true)) { p3c = true }
                }
            }
        }.ignoresSafeArea()
    }

    private func blob(_ color: Color, _ g: GeometryProxy, x: CGFloat, y: CGFloat,
                      size: CGFloat, blur: CGFloat, opacity: Double,
                      dxA: CGFloat, dyA: CGFloat, scaleA: CGFloat, rotA: Double,
                      pA: Bool, pB: Bool, pC: Bool) -> some View {
        let side = g.size.width * size
        return RoundedRectangle(cornerRadius: side * 0.48, style: .continuous)
            .fill(color).frame(width: side, height: side)
            .blur(radius: blur).opacity(opacity)
            .position(x: g.size.width * (x + 0.45), y: g.size.height * (y + 0.45))
            // 3 independent animations → position, scale, rotation never sync
            .offset(x: pA ? g.size.width * dxA : 0, y: pA ? g.size.height * dyA : 0)
            .scaleEffect(pB ? scaleA : 0.92)  // scale breathes independently
            .rotationEffect(.degrees(pC ? rotA : -rotA * 0.5))  // rotation oscillates independently
    }
}



