// Plink/Design/Cinematic/CinematicMotion.swift — Motion presets
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §1: Motion

import SwiftUI

public enum CinemaMotion {
    public static let fast = Animation.easeOut(duration: 0.18)
    public static let standard = Animation.easeInOut(duration: 0.25)
    public static let slow = Animation.easeInOut(duration: 0.4)
    public static let spring = Animation.spring(duration: 0.35, bounce: 0.06)
    public static let heroTransition = Animation.spring(duration: 0.42, bounce: 0.08)
}

// MARK: - Shimmer loading effect

struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Cinema2026.surface)
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            Cinema2026.raised.opacity(0.4),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase * geo.size.width)
                    .mask(Rectangle())
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

// MARK: - Hover scale (macOS / iPad)

struct HoverScale: ViewModifier {
    @State private var isHovered = false
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .onHover { isHovered = $0 }
            .animation(CinemaMotion.fast, value: isHovered)
    }
}

extension View {
    func hoverScale(_ scale: CGFloat = 1.025) -> some View {
        modifier(HoverScale(scale: scale))
    }
}
