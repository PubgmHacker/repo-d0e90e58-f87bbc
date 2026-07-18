// Plink/Design/Cinematic/AICompanionModel.swift
//
// Canvas-based AI Companion orb — state-reactive, no Metal dependency.
// Replaces the old MetalVideoBackground approach with pure SwiftUI Canvas.
//
// States: idle → listening → thinking → speaking
// Each state changes orb color, pulse speed, and glow intensity.

import SwiftUI

// MARK: - AI Companion State

enum AICompanionState: String, CaseIterable, Codable {
    case idle
    case listening
    case thinking
    case speaking
}

// MARK: - AI Companion Orb View

struct AICompanionOrb: View {
    let state: AICompanionState
    var size: CGFloat = 120

    @State private var phase: Double = 0
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if reduceMotion {
                // Static orb for Reduce Motion
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [stateColor.opacity(0.8), stateColor.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.6
                        )
                    )
                    .frame(width: size, height: size)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, canvasSize in
                        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                        let baseRadius = min(canvasSize.width, canvasSize.height) * 0.35

                        // Outer glow (pulsing)
                        let glowRadius = baseRadius * (1.0 + sin(t * statePulseSpeed) * 0.15)
                        let glowGradient = Gradient(colors: [stateColor.opacity(0.4), Color.clear])
                        ctx.fill(
                            Path(ellipseIn: CGRect(
                                x: center.x - glowRadius * 1.5,
                                y: center.y - glowRadius * 1.5,
                                width: glowRadius * 3,
                                height: glowRadius * 3
                            )),
                            with: .radialGradient(glowGradient, center: center, startRadius: 0, endRadius: glowRadius * 1.5)
                        )

                        // Main orb body
                        let orbRadius = baseRadius * (1.0 + sin(t * statePulseSpeed * 1.3) * 0.08)
                        let orbGradient = Gradient(colors: [
                            stateColor.opacity(0.9),
                            stateColor.opacity(0.5),
                            stateColor.opacity(0.2),
                        ])
                        ctx.fill(
                            Path(ellipseIn: CGRect(
                                x: center.x - orbRadius,
                                y: center.y - orbRadius,
                                width: orbRadius * 2,
                                height: orbRadius * 2
                            )),
                            with: .radialGradient(orbGradient, center: center, startRadius: 0, endRadius: orbRadius)
                        )

                        // Inner highlight (offset for 3D effect)
                        let highlightRadius = orbRadius * 0.3
                        let highlightOffset = CGPoint(
                            x: center.x - orbRadius * 0.3,
                            y: center.y - orbRadius * 0.3
                        )
                        let highlightGradient = Gradient(colors: [Color.white.opacity(0.3), Color.clear])
                        ctx.fill(
                            Path(ellipseIn: CGRect(
                                x: highlightOffset.x - highlightRadius,
                                y: highlightOffset.y - highlightRadius,
                                width: highlightRadius * 2,
                                height: highlightRadius * 2
                            )),
                            with: .radialGradient(highlightGradient, center: highlightOffset, startRadius: 0, endRadius: highlightRadius)
                        )

                        // Orbital rings (for thinking/speaking states)
                        if state == .thinking || state == .speaking {
                            for i in 0..<3 {
                                let ringRadius = orbRadius * (1.2 + CGFloat(i) * 0.15)
                                let ringPhase = t * (2.0 + Double(i) * 0.5) + Double(i) * 2.0
                                let ringAlpha = 0.15 + sin(ringPhase) * 0.1
                                ctx.stroke(
                                    Path(ellipseIn: CGRect(
                                        x: center.x - ringRadius,
                                        y: center.y - ringRadius,
                                        width: ringRadius * 2,
                                        height: ringRadius * 2
                                    )),
                                    with: .color(stateColor.opacity(ringAlpha)),
                                    lineWidth: 1.5
                                )
                            }
                        }
                    }
                    .frame(width: size, height: size)
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    // MARK: - State-based colors

    private var stateColor: Color {
        switch state {
        case .idle:       return Color(hex: 0x2DE2E6)  // cyan — calm
        case .listening:  return Color(hex: 0x26D9A4)  // emerald — active
        case .thinking:   return Color(hex: 0xD7A750)  // amber — processing
        case .speaking:   return Color(hex: 0x2DE2E6)  // cyan — output
        }
    }

    private var statePulseSpeed: Double {
        switch state {
        case .idle:       return 0.8   // slow, calm
        case .listening:  return 2.0   // medium, alert
        case .thinking:   return 4.0   // fast, processing
        case .speaking:   return 3.0   // rhythmic
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AI Orb — Idle") {
    AICompanionOrb(state: .idle, size: 120)
        .padding(40)
        .background(Cinema2026.background)
        .preferredColorScheme(.dark)
}

#Preview("AI Orb — Thinking") {
    AICompanionOrb(state: .thinking, size: 120)
        .padding(40)
        .background(Cinema2026.background)
        .preferredColorScheme(.dark)
}
#endif
