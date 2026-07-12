// Plink/Features/WatchRoom/WatchRoomSocialRegion.swift — GPT-5.6 Final §4
//
// Themed room social region: chat, presence, AI banner, composer.
// Player viewport is NEVER decorated — theme applies only here.
import SwiftUI

struct WatchRoomSocialRegion: View {
    @Bindable var model: WatchRoomModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // GPT-5.6 Final §4: theme at 38-48% intensity for chat surface
            PlinkLivingBackground(theme: model.roomTheme, surface: .chat)

            // GPT-5.6 Final §4: opaque overlay for readability + Reduce Transparency
            Color.black.opacity(reduceTransparency ? 0.88 : 0.48)

            VStack(spacing: 0) {
                PresenceBar(model: model)
                if model.aiAssistantEnabled {
                    RoomAIAssistantBanner(state: model.aiState)
                }
                WatchChatView(model: model)
                WatchChatComposer(model: model)
            }
        }
        .clipped()
    }
}

// GPT-5.6 Final §3: Neutral player container — NO decoration
struct NeutralPlayerContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
        // NO .glassCard, .neonGlow, .shadow, theme material or animated palette
    }
}

// GPT-5.6 Final §5: Chat bubble colors — explicit surfaces, not blur
enum ThemedChatBubbleStyle {
    static let incoming = Color(red: 0.105, green: 0.125, blue: 0.135).opacity(0.94)
    static let outgoing = Cinema2026.accent.opacity(0.96)
    static let system = Color(red: 0.20, green: 0.16, blue: 0.06).opacity(0.96)
    static let moderated = Color(red: 0.20, green: 0.07, blue: 0.07).opacity(0.96)
}

// GPT-5.6 Final §6: Verified AI message model
struct RoomChatMessage: Identifiable, Sendable {
    enum Sender: Sendable {
        case user(id: String, displayName: String)
        case plinkAI
        case system
    }
    enum ModerationPresentation: Sendable {
        case none
        case hidden(reasonCode: String)
        case warned(reasonCode: String)
    }
    let id: String
    let sender: Sender
    let text: String
    let moderation: ModerationPresentation
}

// GPT-5.6 Final §7: Room moderation level
enum RoomModerationLevel: String, Sendable, Codable {
    case standard = "STANDARD"
    case strict = "STRICT"
}
