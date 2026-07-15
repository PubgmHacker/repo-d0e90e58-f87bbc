// Plink/Design/Cinematic/CompactLivingBackdrop.swift — §7 Final Unified
//
// Subtle ambient backdrop with accessibility + power gating + memory optimization.
//
// P1/P2 Sprint fix:
// - Pause animation when view disappears (`.onDisappear`)
// - Stop animations on background (scenePhase != .active)
// - Reduce Motion → static gradient (no animation, no timer)
// - Reduce Transparency → flat tinted background
// - 30-min memory test safe (no Timer, no infinite retains)

import SwiftUI

struct CompactLivingBackdrop: View {
    let primary: Color
    let secondary: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = false
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Cinema2026.background

            // Reduce Motion → static gradient (no animation, no CPU)
            if reduceMotion {
                LinearGradient(
                    colors: [
                        Cinema2026.background,
                        primary.opacity(0.06),
                        Cinema2026.background,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if !reduceTransparency {
                // Animated orbs — only when active + visible
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
            } else {
                // Reduce Transparency → flat tinted background
                Cinema2026.background.opacity(0.95)
            }
        }
        // MARK: - Memory optimization: start/stop animation based on lifecycle
        .onAppear {
            isVisible = true
            startAnimationIfNeeded()
        }
        .onDisappear {
            // CRITICAL: stop animation when view leaves hierarchy
            isVisible = false
            withAnimation(.linear(duration: 0.2)) {
                phase = false
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // App came to foreground — resume animation
                startAnimationIfNeeded()
            case .background, .inactive:
                // App backgrounded — STOP animation (saves battery + memory)
                phase = false
            @unknown default:
                break
            }
        }
    }

    // MARK: - Animation controller
    private func startAnimationIfNeeded() {
        // Skip if Reduce Motion or view not visible or app not active
        guard isVisible, !reduceMotion, scenePhase == .active else { return }

        // Reset and start fresh — prevents animation accumulation
        phase = false
        withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
            phase = true
        }
    }
}

// MARK: - Memory-safe variant for long-running screens (WatchRoom)

/// Use this variant in WatchRoom and other long-lived screens.
/// It uses TimelineView instead of repeatForever to allow
/// automatic pausing when view is not visible.
struct MemorySafeLivingBackdrop: View {
    let primary: Color
    let secondary: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Cinema2026.background

            if reduceMotion {
                LinearGradient(
                    colors: [
                        Cinema2026.background,
                        primary.opacity(0.06),
                        Cinema2026.background,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if !reduceTransparency && scenePhase == .active {
                // TimelineView pauses automatically when view is not visible
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let w = size.width
                        let h = size.height

                        // Orb 1 — primary (top-left drift)
                        let orb1X = w * 0.3 + sin(t * 0.4) * 60
                        let orb1Y = h * 0.3 + cos(t * 0.3) * 40
                        drawOrb(
                            in: ctx,
                            center: CGPoint(x: orb1X, y: orb1Y),
                            radius: 130,
                            color: primary.opacity(0.18)
                        )

                        // Orb 2 — secondary (bottom-right drift)
                        let orb2X = w * 0.7 + cos(t * 0.35) * 70
                        let orb2Y = h * 0.7 + sin(t * 0.45) * 50
                        drawOrb(
                            in: ctx,
                            center: CGPoint(x: orb2X, y: orb2Y),
                            radius: 115,
                            color: secondary.opacity(0.13)
                        )
                    }
                }
            } else {
                Cinema2026.background.opacity(0.95)
            }
        }
    }

    private func drawOrb(
        in ctx: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        // GraphicsContext doesn't support .filter blur directly.
        // Use radial gradient instead to simulate soft glow.
        let gradient = GraphicsContext.Shading.color(
            RadialGradient(
                colors: [color, color.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: radius
            )
        )
        ctx.fill(Path(ellipseIn: rect), with: gradient)
    }
}
