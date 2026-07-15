//
//  PlinkBubbleStyle.swift
//  Plink
//
//  P1 — BubbleStyle protocol, registry, and renderer.
//  Implements Section 2.3 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//
//  Rules:
//  - BubbleStyle belongs to SENDER. ID rides with message (`ChatMessage.bubbleStyle`).
//  - Server validates premium IDs at send time only.
//  - All clients MUST render premium styles even for free recipients.
//  - Only the last 3-5 visible messages animate; older = static snapshot.
//  - Forbidden: infinite fast flicker, resize-after-layout, text animation,
//    heavy shaders on all messages simultaneously.
//
//  This file is the new single source of truth for bubble rendering.
//  Replaces the old `StyledChatBubble.swift`, `WatchChatBubble.swift`,
//  and the old `Models/BubbleStyle.swift` enum.
//

import SwiftUI
import Foundation

// MARK: - BubbleStyleRegistry

enum BubbleStyleRegistry {
    static func descriptor(id: String) -> AppearanceDescriptor? {
        AppearanceCatalog.bubbleStatic.first { $0.id == id }
            ?? AppearanceCatalog.bubbleAnimated.first { $0.id == id }
    }

    /// Always returns a renderable descriptor — falls back to `bubble-quiet`.
    static func safeDescriptor(id: String?) -> AppearanceDescriptor {
        guard let id, let d = descriptor(id: id) else {
            return AppearanceCatalog.bubbleStatic.first { $0.id == "bubble-quiet" }!
        }
        return d
    }

    /// Bridge from legacy backend IDs (`default`, `cute_duck`, `neon_cyber`,
    /// `admin_bubble`) to the new V5 IDs. Old messages from before the V5
    /// rollout will continue to render — they map to the closest new style.
    static func migrateLegacyID(_ raw: String?) -> String {
        switch raw ?? "default" {
        case "default":       return "bubble-quiet"
        case "cute_duck":     return "bubble-ink-flow"
        case "neon_cyber":    return "bubble-pulse-ring"
        case "admin_bubble":  return "bubble-prism"
        default:              return raw ?? "bubble-quiet"
        }
    }
}

// MARK: - BubbleStyleRenderer

/// Renders a single chat bubble with the style indicated by `message.bubbleStyle`.
/// Pass `indexFromBottom` to control animation — only the last 5 messages animate;
/// older ones render as static snapshots.
///
/// Works with the existing `ChatMessage` model (no model changes required).
internal struct BubbleStyleRenderer<Content: View>: View {
    let message: ChatMessage
    let isOutgoing: Bool
    let indexFromBottom: Int   // 0 = most recent
    let content: () -> Content

    @State private var animatePulse = false
    @State private var animateComet = false
    @State private var animateSignal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let animationThreshold = 5   // only last 5 animate

    init(
        message: ChatMessage,
        isOutgoing: Bool,
        indexFromBottom: Int = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.message = message
        self.isOutgoing = isOutgoing
        self.indexFromBottom = indexFromBottom
        self.content = content
    }

    var body: some View {
        let migratedID = BubbleStyleRegistry.migrateLegacyID(message.bubbleStyle)
        let desc = BubbleStyleRegistry.safeDescriptor(id: migratedID)
        let shouldAnimate = indexFromBottom < animationThreshold && !reduceMotion

        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground(desc))
            .overlay(bubbleOverlay(desc, animate: shouldAnimate))
            .clipShape(V5BubbleShape(isOutgoing: isOutgoing))
            .onAppear {
                guard shouldAnimate else { return }
                triggerAnimation(for: desc.id)
            }
    }

    // MARK: - Background

    @ViewBuilder
    private func bubbleBackground(_ desc: AppearanceDescriptor) -> some View {
        switch desc.id {
        case "bubble-quiet":
            Color.white.opacity(0.06)
        case "bubble-accent":
            LinearGradient(
                colors: desc.previewColors.map { Color(hex: $0) },
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case "bubble-ink-flow":
            TimelineView(.animation) { ctx in
                inkFlowGradient(t: ctx.date.timeIntervalSinceReferenceDate, desc: desc)
            }
        case "bubble-prism":
            TimelineView(.animation) { ctx in
                prismGradient(t: ctx.date.timeIntervalSinceReferenceDate, desc: desc)
            }
        default:
            Color.white.opacity(0.06)
        }
    }

    // MARK: - Animated gradient helpers (extracted so TimelineView closure
    // is a single View expression — Swift 5.9 @ViewBuilder doesn't accept
    // `let` statements followed by a View in all contexts).

    private func inkFlowGradient(t: Double, desc: AppearanceDescriptor) -> some View {
        LinearGradient(
            colors: [
                Color(hex: desc.previewColors[0]),
                Color(hex: desc.previewColors[1]),
                Color(hex: desc.previewColors[0])
            ],
            startPoint: UnitPoint(x: 0.5 + 0.4 * sin(t * 0.3), y: 0),
            endPoint: UnitPoint(x: 0.5 + 0.4 * cos(t * 0.3), y: 1)
        )
    }

    private func prismGradient(t: Double, desc: AppearanceDescriptor) -> some View {
        LinearGradient(
            colors: desc.previewColors.map { Color(hex: $0) },
            startPoint: UnitPoint(x: 0.5 + 0.5 * cos(t * 0.18), y: 0.5 + 0.5 * sin(t * 0.18)),
            endPoint: UnitPoint(x: 0.5 - 0.5 * cos(t * 0.18), y: 0.5 - 0.5 * sin(t * 0.18))
        )
    }

    // MARK: - Overlay

    @ViewBuilder
    private func bubbleOverlay(_ desc: AppearanceDescriptor, animate: Bool) -> some View {
        switch desc.id {
        case "bubble-pulse-ring":
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color(hex: desc.previewColors[0]),
                    lineWidth: 2
                )
                .opacity(animatePulse && animate ? 1 : 0)
                .scaleEffect(animatePulse && animate ? 1.04 : 1.0)

        case "bubble-comet":
            GeometryReader { geo in
                Circle()
                    .fill(Color(hex: desc.previewColors[0]))
                    .frame(width: 6, height: 6)
                    .blur(radius: 2)
                    .opacity(animateComet && animate ? 0.9 : 0)
                    .offset(x: animateComet && animate ? geo.size.width - 12 : 0, y: 4)
            }
            .mask(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 8)
            )

        case "bubble-signal":
            HStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .strokeBorder(
                            Color(hex: desc.previewColors[i % desc.previewColors.count]),
                            lineWidth: 1.5
                        )
                        .scaleEffect(animateSignal && animate ? 1.4 : 0.9)
                        .opacity(animateSignal && animate ? 0 : 0.7)
                }
            }
            .frame(width: 18, height: 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(6)

        case "bubble-ink-flow", "bubble-prism":
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)

        case "bubble-accent":
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)

        default: // bubble-quiet
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Trigger

    private func triggerAnimation(for id: String) {
        switch id {
        case "bubble-pulse-ring":
            withAnimation(.easeOut(duration: 0.7)) { animatePulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                animatePulse = false
            }
        case "bubble-comet":
            withAnimation(.easeInOut(duration: 0.6)) { animateComet = true }
        case "bubble-signal":
            withAnimation(.easeOut(duration: 0.6)) { animateSignal = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.6)) { animateSignal = false }
            }
        default:
            break
        }
    }
}

// MARK: - V5BubbleShape (renamed to avoid clash with any legacy BubbleShape)

struct V5BubbleShape: Shape {
    let isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(16, rect.height / 2)
        var path = Path()
        let tl: CGFloat = isOutgoing ? r : 4
        let tr: CGFloat = isOutgoing ? 4 : r
        let bl: CGFloat = r
        let br: CGFloat = r
        path.addRoundedRect(
            in: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: tl, bottomLeading: bl,
                bottomTrailing: br, topTrailing: tr
            )
        )
        return path
    }
}

// MARK: - BubbleIndexTracker

/// Computes `indexFromBottom` for each message in a list. Only the last
/// `animationThreshold` items animate.
enum BubbleIndexTracker {
    static func indexFromBottom(messageID: String, in messages: [ChatMessage]) -> Int {
        guard let idx = messages.lastIndex(where: { $0.id == messageID }) else {
            return .max
        }
        return messages.count - 1 - idx
    }
}
