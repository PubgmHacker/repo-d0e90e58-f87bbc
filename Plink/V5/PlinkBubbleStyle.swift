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
        case "cute_duck":     return "bubble-frame-cat"   // legacy cute → TikTok cat frame
        case "neon_cyber":    return "bubble-pulse-ring"
        case "admin_bubble":  return "bubble-prism"
        case "bubble-ink-flow": return "bubble-frame-unicorn"
        case "bubble-comet":    return "bubble-frame-stars"
        case "bubble-signal":   return "bubble-frame-rainbow"
        default:              return raw ?? "bubble-quiet"
        }
    }
}

// MARK: - TikTok-style frame models (decorative borders + animal corners)

/// One “frame model” — like TikTok chat frames: fill, border, corner mascots.
enum BubbleFrameModel: String, CaseIterable, Sendable {
    case quiet
    case accent
    case cat
    case dog
    case hearts
    case bunny
    case panda
    case fox
    case bear
    case unicorn
    case dino
    case stars
    case flowers
    case rainbow
    case frog
    case pulse
    case prism

    static func resolve(styleID: String?) -> BubbleFrameModel {
        let id = BubbleStyleRegistry.migrateLegacyID(styleID)
        switch id {
        case "bubble-quiet": return .quiet
        case "bubble-accent": return .accent
        case "bubble-frame-cat": return .cat
        case "bubble-frame-dog": return .dog
        case "bubble-frame-hearts": return .hearts
        case "bubble-frame-bunny": return .bunny
        case "bubble-frame-panda": return .panda
        case "bubble-frame-fox": return .fox
        case "bubble-frame-bear": return .bear
        case "bubble-frame-unicorn": return .unicorn
        case "bubble-frame-dino": return .dino
        case "bubble-frame-stars": return .stars
        case "bubble-frame-flowers": return .flowers
        case "bubble-frame-rainbow": return .rainbow
        case "bubble-frame-frog": return .frog
        case "bubble-pulse-ring": return .pulse
        case "bubble-prism": return .prism
        default: return .quiet
        }
    }

    /// Corner stickers (TikTok puts animals on frame corners).
    var cornerEmojis: (tl: String?, tr: String?, bl: String?, br: String?) {
        switch self {
        case .quiet, .accent, .pulse, .prism:
            return (nil, nil, nil, nil)
        case .cat:
            return ("🐱", "🐱", "🐾", "🐾")
        case .dog:
            return ("🐶", "🐶", "🦴", "🐾")
        case .hearts:
            return ("💕", "💖", "💗", "💘")
        case .bunny:
            return ("🐰", "🐰", "🥕", "✨")
        case .panda:
            return ("🐼", "🐼", "🎋", "🍃")
        case .fox:
            return ("🦊", "🦊", "🍂", "✨")
        case .bear:
            return ("🐻", "🐻", "🍯", "💤")
        case .unicorn:
            return ("🦄", "✨", "🌈", "💫")
        case .dino:
            return ("🦕", "🦕", "🌿", "🥚")
        case .stars:
            return ("⭐", "✨", "🌙", "💫")
        case .flowers:
            return ("🌸", "🌼", "🌺", "🌷")
        case .rainbow:
            return ("🌈", "✨", "☁️", "💛")
        case .frog:
            return ("🐸", "🐸", "🍃", "💚")
        }
    }

    var borderColors: [Color] {
        switch self {
        case .quiet: return [Color.white.opacity(0.14)]
        case .accent: return [Color(hex: "#00D4FF"), Color(hex: "#3FE8C8")]
        case .cat: return [Color(hex: "#FF8DC7"), Color(hex: "#FFC6E8"), Color(hex: "#FF6BB5")]
        case .dog: return [Color(hex: "#F5A962"), Color(hex: "#FFD4A3")]
        case .hearts: return [Color(hex: "#FF6B9D"), Color(hex: "#FFB3C7")]
        case .bunny: return [Color(hex: "#E8D5FF"), Color(hex: "#C4B5FD")]
        case .panda: return [Color.white.opacity(0.9), Color.black.opacity(0.55)]
        case .fox: return [Color(hex: "#FF7A18"), Color(hex: "#FFD29D")]
        case .bear: return [Color(hex: "#A67C52"), Color(hex: "#E8C4A0")]
        case .unicorn: return [Color(hex: "#F0ABFC"), Color(hex: "#A5B4FC"), Color(hex: "#67E8F9")]
        case .dino: return [Color(hex: "#4ADE80"), Color(hex: "#86EFAC")]
        case .stars: return [Color(hex: "#6366F1"), Color(hex: "#FDE68A")]
        case .flowers: return [Color(hex: "#FB7185"), Color(hex: "#F9A8D4")]
        case .rainbow: return [
            Color(hex: "#F87171"), Color(hex: "#FBBF24"),
            Color(hex: "#34D399"), Color(hex: "#60A5FA"), Color(hex: "#A78BFA")
        ]
        case .frog: return [Color(hex: "#4ADE80"), Color(hex: "#BBF7D0")]
        case .pulse: return [Color(hex: "#3FE8C8"), Color(hex: "#00D4FF")]
        case .prism: return [Color(hex: "#F59E0B"), Color(hex: "#3FE8C8"), Color(hex: "#A855F7")]
        }
    }

    var fillColors: [Color] {
        switch self {
        case .quiet:
            return [Color.white.opacity(0.12)]
        case .accent, .pulse:
            return [Color(hex: "#00D4FF").opacity(0.88), Color(hex: "#3FE8C8").opacity(0.75)]
        case .cat:
            return [Color(hex: "#3D1F33").opacity(0.92), Color(hex: "#5A2A48").opacity(0.88)]
        case .dog:
            return [Color(hex: "#3A2618").opacity(0.92), Color(hex: "#5C3A22").opacity(0.88)]
        case .hearts:
            return [Color(hex: "#3B1528").opacity(0.92), Color(hex: "#5C1F3D").opacity(0.9)]
        case .bunny:
            return [Color(hex: "#2A2040").opacity(0.92), Color(hex: "#3D2F5C").opacity(0.9)]
        case .panda:
            return [Color(hex: "#1A1A1A").opacity(0.92), Color(hex: "#2C2C2C").opacity(0.9)]
        case .fox:
            return [Color(hex: "#3A1E0C").opacity(0.92), Color(hex: "#5C3014").opacity(0.9)]
        case .bear:
            return [Color(hex: "#2A1C12").opacity(0.92), Color(hex: "#3F2A1A").opacity(0.9)]
        case .unicorn:
            return [Color(hex: "#2A1840").opacity(0.92), Color(hex: "#1E2A4A").opacity(0.9)]
        case .dino:
            return [Color(hex: "#14281A").opacity(0.92), Color(hex: "#1F3D28").opacity(0.9)]
        case .stars:
            return [Color(hex: "#12142E").opacity(0.94), Color(hex: "#1C1F48").opacity(0.9)]
        case .flowers:
            return [Color(hex: "#2E1524").opacity(0.92), Color(hex: "#3F1E32").opacity(0.9)]
        case .rainbow:
            return [Color(hex: "#1A1A2E").opacity(0.92), Color(hex: "#252545").opacity(0.9)]
        case .frog:
            return [Color(hex: "#142A18").opacity(0.92), Color(hex: "#1F3D24").opacity(0.9)]
        case .prism:
            return [Color(hex: "#1A1430").opacity(0.92), Color(hex: "#2A1F48").opacity(0.9)]
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .quiet: return 0.8
        case .accent, .pulse: return 1.6
        case .rainbow, .unicorn, .prism: return 2.4
        default: return 2.0
        }
    }

    var isDecorative: Bool {
        switch self {
        case .quiet, .accent, .pulse, .prism: return false
        default: return true
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

/// Telegram-like capsule bubble: large continuous corners; slight tail cut
/// only on the last message of a group (via isLastInGroup on the parent).
struct V5BubbleShape: Shape {
    let isOutgoing: Bool
    /// When false (middle of chain), use fully rounded capsule corners.
    var isLastInGroup: Bool = true

    func path(in rect: CGRect) -> Path {
        // Capsule-like: corner radius ~ half height, capped for wide bubbles
        let r = min(18, rect.height / 2)
        var path = Path()
        // Telegram: slightly tighter corner on the "tail" side of last bubble
        let tail: CGFloat = isLastInGroup ? 6 : r
        let tl: CGFloat = isOutgoing ? r : (isLastInGroup ? tail : r)
        let tr: CGFloat = isOutgoing ? (isLastInGroup ? tail : r) : r
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

// MARK: - User preference (Оформление → Бабл-стиль)

enum PlinkBubbleStylePrefs {
    static let storageKey = "plink.bubbleStyleID"

    static var currentID: String {
        UserDefaults.standard.string(forKey: storageKey)
            ?? AppearanceCatalog.defaultBubbleStyleID
    }

    static func set(_ id: String) {
        UserDefaults.standard.set(id, forKey: storageKey)
        NotificationCenter.default.post(name: .plinkBubbleStyleChanged, object: id)
    }

    static var allStyles: [AppearanceDescriptor] {
        AppearanceCatalog.bubbleStatic + AppearanceCatalog.bubbleAnimated
    }
}

extension Notification.Name {
    static let plinkBubbleStyleChanged = Notification.Name("plink.bubbleStyleChanged")
}

// MARK: - Wire format (style rides with message text — all clients see it)

/// Embeds the sender's bubble style into message text so every device can
/// render it without relying on local preferences.
/// Format: `[[bs:STYLE_ID]]actual message text`
enum PlinkBubbleWire {
    private static let prefix = "[[bs:"
    private static let suffix = "]]"

    /// Encode style for transport. Free-tier safe styles always allowed;
    /// premium IDs still travel so free recipients can *see* them.
    static func encode(text: String, styleID: String?) -> String {
        let raw = (styleID ?? PlinkBubbleStylePrefs.currentID).trimmingCharacters(in: .whitespacesAndNewlines)
        let id = BubbleStyleRegistry.migrateLegacyID(raw.isEmpty ? nil : raw)
        // Strip accidental nested markers from body
        let body = decode(text).text
        return "\(prefix)\(id)\(suffix)\(body)"
    }

    static func decode(_ raw: String) -> (styleID: String?, text: String) {
        guard raw.hasPrefix(prefix),
              let end = raw.range(of: suffix) else {
            return (nil, raw)
        }
        let idStart = raw.index(raw.startIndex, offsetBy: prefix.count)
        let id = String(raw[idStart..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(raw[end.upperBound...])
        guard !id.isEmpty, id.count <= 64, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return (nil, raw)
        }
        return (BubbleStyleRegistry.migrateLegacyID(id), body)
    }
}

// MARK: - Telegram-style message clustering

/// Avatar + name only on group edges (like Telegram).
struct ChatClusterLayout: Equatable {
    /// Show avatar on this row (last message of consecutive same-sender group).
    let showAvatar: Bool
    /// Show sender name (first message of group, incoming only).
    let showName: Bool
    /// First bubble in a same-sender run.
    let isFirstInGroup: Bool
    /// Last bubble in a same-sender run.
    let isLastInGroup: Bool
    /// Spacing *before* this row.
    let topPadding: CGFloat

    static func compute(
        senderId: String,
        previousSenderId: String?,
        nextSenderId: String?,
        isOwn: Bool
    ) -> ChatClusterLayout {
        let samePrev = previousSenderId == senderId
        let sameNext = nextSenderId == senderId
        return ChatClusterLayout(
            showAvatar: !sameNext,
            showName: !isOwn && !samePrev,
            isFirstInGroup: !samePrev,
            isLastInGroup: !sameNext,
            topPadding: samePrev ? 2 : 10
        )
    }
}

// MARK: - Shared bubble for DM + room chat (TikTok frames + glass capsules)

/// Renders text with the **sender's** bubble / frame style.
/// TikTok-style models add animal corners + colored borders (synced via wire).
struct PlinkMessageBubble: View {
    let text: String
    let isOwn: Bool
    /// Sender style ID from the message (not local prefs for peers).
    var styleID: String? = nil
    var fontSize: CGFloat = 15
    /// Telegram tail: only last in group gets the "pointy" corner.
    var isLastInGroup: Bool = true

    private var frame: BubbleFrameModel {
        if let styleID, !styleID.isEmpty {
            return BubbleFrameModel.resolve(styleID: styleID)
        }
        if isOwn {
            return BubbleFrameModel.resolve(styleID: PlinkBubbleStylePrefs.currentID)
        }
        return .quiet
    }

    private var shape: V5BubbleShape {
        V5BubbleShape(isOutgoing: isOwn, isLastInGroup: isLastInGroup)
    }

    var body: some View {
        // Extra inset for decorative frames so mascots sit outside the text
        let padH: CGFloat = frame.isDecorative ? 18 : 14
        let padV: CGFloat = frame.isDecorative ? 12 : 10
        let outer: CGFloat = frame.isDecorative ? 10 : 0

        MessageRichText(text: text, fontSize: fontSize)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .background(fillLayer)
            .clipShape(shape)
            .overlay(borderLayer)
            .overlay(alignment: .center) {
                if frame.isDecorative {
                    TikTokFrameDecor(frame: frame)
                }
            }
            .padding(outer)
            .shadow(
                color: frame.isDecorative
                    ? frame.borderColors.first?.opacity(0.35) ?? .black.opacity(0.2)
                    : .black.opacity(0.22),
                radius: frame.isDecorative ? 10 : 6,
                y: 2
            )
    }

    @ViewBuilder
    private var fillLayer: some View {
        switch frame {
        case .quiet:
            if isOwn {
                LinearGradient(
                    colors: [
                        Cinema2026.accent.opacity(0.88),
                        Cinema2026.accent.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.white.opacity(0.12)
            }
        default:
            LinearGradient(
                colors: frame.fillColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        if frame.borderColors.count >= 2 {
            shape
                .stroke(
                    AngularGradient(
                        colors: frame.borderColors + [frame.borderColors[0]],
                        center: .center
                    ),
                    lineWidth: frame.borderWidth
                )
        } else {
            shape
                .stroke(
                    frame.borderColors.first ?? Color.white.opacity(0.12),
                    lineWidth: frame.borderWidth
                )
        }
    }
}

// MARK: - TikTok frame decorations (corner mascots)

/// Animals / stickers sit on bubble corners — same idea as TikTok message frames.
private struct TikTokFrameDecor: View {
    let frame: BubbleFrameModel

    var body: some View {
        let c = frame.cornerEmojis
        GeometryReader { geo in
            let s: CGFloat = min(22, max(16, geo.size.height * 0.28))
            ZStack {
                if let e = c.tl {
                    Text(e).font(.system(size: s))
                        .position(x: 2, y: 2)
                        .offset(x: s * 0.15, y: s * 0.1)
                }
                if let e = c.tr {
                    Text(e).font(.system(size: s))
                        .position(x: geo.size.width - 2, y: 2)
                        .offset(x: -s * 0.15, y: s * 0.1)
                }
                if let e = c.bl {
                    Text(e).font(.system(size: s * 0.85))
                        .position(x: 4, y: geo.size.height - 2)
                        .offset(x: s * 0.1, y: -s * 0.1)
                }
                if let e = c.br {
                    Text(e).font(.system(size: s * 0.85))
                        .position(x: geo.size.width - 4, y: geo.size.height - 2)
                        .offset(x: -s * 0.1, y: -s * 0.1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
