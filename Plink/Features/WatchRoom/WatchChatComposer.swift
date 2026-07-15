// Plink/Features/WatchRoom/WatchChatComposer.swift — PATCH 26: Telegram-style emoji
//
// PATCH 26: inline emoji panel (Telegram-style) instead of popover.

import SwiftUI

struct WatchChatComposer: View {
    let model: WatchRoomModel

    @State private var state = ChatComposerState()
    @State private var showEmojiPanel = false
    @State private var currentPackIndex = 0
    @State private var showPacksPopover = false

    private var canSend: Bool {
        state.canSend(connected: model.connectionState == .connected)
    }

    private var hasPremium: Bool {
        PremiumStatusManager.shared.isPremium
    }

    private let emojiPacks: [EmojiPack] = [
        EmojiPack(name: "Reactions", emojis: ["emoji_laugh", "emoji_fire", "emoji_heart", "emoji_thumbs_up", "emoji_thumbs_down", "emoji_scream", "emoji_cry", "emoji_love", "emoji_think", "emoji_cool", "emoji_party", "emoji_angry", "emoji_sad", "emoji_wow", "emoji_sleepy", "emoji_clap", "emoji_pray", "emoji_ok", "emoji_poop", "emoji_flex"], isPremium: false),
        EmojiPack(name: "Plink+", emojis: ["emoji_neon_laugh", "emoji_neon_fire", "emoji_neon_heart", "emoji_neon_thumbs_up", "emoji_neon_party", "emoji_neon_cool", "emoji_neon_wow", "emoji_neon_clap"], isPremium: true),
        EmojiPack(name: "Fun", emojis: ["emoji_popcorn", "emoji_movie", "emoji_clapper", "emoji_director", "emoji_oscar", "emoji_ticket", "emoji_film", "emoji_camera"], isPremium: true),
    ]

    private var currentPack: EmojiPack {
        guard currentPackIndex >= 0 && currentPackIndex < emojiPacks.count else { return emojiPacks[0] }
        return emojiPacks[currentPackIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // PATCH 26: inline emoji panel (Telegram-style)
            if showEmojiPanel {
                EmojiInlinePanel(
                    pack: currentPack,
                    hasPremium: hasPremium,
                    onPick: { emoji in
                        state.insertAtCursor(emoji)
                    },
                    onPremiumUpsell: {
                        showEmojiPanel = false
                    },
                    onSwitchPack: { index in
                        currentPackIndex = index
                    },
                    packs: emojiPacks
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showEmojiPanel.toggle()
                    }
                } label: {
                    Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling")
                        .font(.system(size: 17))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(width: 40, height: 40)
                        .background(Cinema2026.raised, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
                }
                .accessibilityLabel("Emoji")
                .onLongPressGesture {
                    showPacksPopover = true
                }
                .popover(isPresented: $showPacksPopover) {
                    PacksPopover(packs: emojiPacks, currentIndex: $currentPackIndex, hasPremium: hasPremium, onDismiss: { showPacksPopover = false })
                }

                VStack(spacing: 4) {
                    TextField("Message…", text: $state.text, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 15))
                        .foregroundStyle(Cinema2026.text)
                        .tint(Cinema2026.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Cinema2026.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(
                                    state.isOverLength ? Cinema2026.danger : .white.opacity(0.05),
                                    lineWidth: state.isOverLength ? 1 : 0.5
                                )
                        )

                    if state.isOverLength {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("\(state.trimmedText.count)/\(ChatComposerState.maxLength) — too long")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Cinema2026.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                }

                Button {
                    let value = state.trimmedText
                    guard state.canSend(connected: model.connectionState == .connected) else { return }
                    model.sendChat(text: value)
                    state.clearAfterSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            canSend
                                ? AnyShapeStyle(Cinema2026.accentAction)
                                : AnyShapeStyle(Cinema2026.raised),
                            in: Circle()
                        )
                        .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
                }
                .disabled(!canSend || state.isOverLength)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Cinema2026.surface.opacity(0.95))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Cinema2026.divider.opacity(0.4))
                    .frame(height: 0.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: .plinkInsertAtCursor)) { note in
                if let insertion = note.userInfo?["text"] as? String {
                    state.insertAtCursor(insertion)
                }
            }
        }
    }
}

// MARK: - Emoji Pack Model (custom packs for Plink+)

struct EmojiPack: Identifiable {
    let id = UUID()
    let name: String
    let emojis: [String]
    let isPremium: Bool
}

// MARK: - Packs Popover (long tap on emoji button → Telegram style)

struct PacksPopover: View {
    let packs: [EmojiPack]
    @Binding var currentIndex: Int
    let hasPremium: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emoji Packs")
                .font(.headline)
                .padding(.horizontal)

            ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                Button {
                    if !pack.isPremium || hasPremium {
                        currentIndex = index
                        onDismiss()
                    }
                } label: {
                    HStack {
                        Text(pack.name)
                            .foregroundStyle(Cinema2026.text)
                        Spacer()
                        if pack.isPremium {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Cinema2026.accent)
                        }
                        if currentIndex == index {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Cinema2026.accent)
                        }
                    }
                    .padding(8)
                    .background(currentIndex == index ? Cinema2026.raised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(pack.isPremium && !hasPremium)
            }

            if !hasPremium {
                Text("Plink+ packs require subscription")
                    .font(.caption)
                    .foregroundStyle(Cinema2026.muted)
                    .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 280)
        .background(Cinema2026.surface)
    }
}

// MARK: - Inline emoji panel (Telegram-style, custom packs)

struct EmojiInlinePanel: View {
    let pack: EmojiPack
    let hasPremium: Bool
    let onPick: (String) -> Void
    let onPremiumUpsell: () -> Void
    let onSwitchPack: (Int) -> Void
    let packs: [EmojiPack]

    var body: some View {
        VStack(spacing: 4) {
            // Pack switcher
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(packs.enumerated()), id: \.element.id) { index, p in
                        Button {
                            if !p.isPremium || hasPremium {
                                onSwitchPack(index)
                            } else {
                                onPremiumUpsell()
                            }
                        } label: {
                            Text(p.name)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(p.id == pack.id ? Cinema2026.accent.opacity(0.2) : Cinema2026.raised)
                                .clipShape(Capsule())
                                .foregroundStyle(p.id == pack.id ? Cinema2026.accent : Cinema2026.text)
                                .overlay {
                                    if p.isPremium && !hasPremium {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8))
                                            .foregroundStyle(Cinema2026.amber)
                                            .offset(x: 8, y: -8)
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(pack.emojis, id: \.self) { emojiName in
                        Button {
                            if pack.isPremium && !hasPremium {
                                onPremiumUpsell()
                            } else {
                                onPick(emojiName)  // pass name; chat will render Image or text
                            }
                        } label: {
                            EmojiAssetImage(name: emojiName, pack: pack.name)
                                .frame(width: 28, height: 28)
                                .opacity(pack.isPremium && !hasPremium ? 0.5 : 1)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 6)
        .background(Cinema2026.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(Cinema2026.divider.opacity(0.4)).frame(height: 0.5)
        }
    }
}

// MARK: - Emoji picker notification

extension Notification.Name {
    static let plinkInsertAtCursor = Notification.Name("plinkInsertAtCursor")
}

// Helper to load custom PNG emoji from bundle Resources/Emojis/<pack>/
struct EmojiAssetImage: View {
    let name: String
    let pack: String

    var body: some View {
        let packDir = pack.lowercased().replacingOccurrences(of: "+", with: "")
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Emojis/\(packDir)"),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
        } else {
            // Fallback to SF Symbol or text
            Image(systemName: "face.smiling")
        }
    }
}
