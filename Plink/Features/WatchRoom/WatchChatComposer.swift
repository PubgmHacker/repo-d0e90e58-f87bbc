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
        // Connected or still negotiating — allow optimistic send
        let online = model.connectionState == .connected || model.connectionState.isTransient
        return state.canSend(connected: online)
    }

    private var hasPremium: Bool {
        PremiumStatusManager.shared.isPremium
    }

    private let emojiPacks: [EmojiPack] = PlinkEmojiCatalog.allPacks

    private var currentPack: EmojiPack {
        guard currentPackIndex >= 0 && currentPackIndex < emojiPacks.count else { return emojiPacks[0] }
        return emojiPacks[currentPackIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Quick reactions (multi-device floating reactions)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReactionPalette.free, id: \.self) { emoji in
                        Button {
                            model.sendReaction(emoji: emoji, hasPremium: hasPremium)
                            HapticManager.impact(.light)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(width: 40, height: 36)
                                .background(Cinema2026.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reaction \(emoji)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // PATCH 26: inline emoji panel (Telegram-style)
            if showEmojiPanel {
                EmojiInlinePanel(
                    pack: currentPack,
                    hasPremium: hasPremium,
                    onPick: { emoji in
                        // Empty field + pick → live reaction; otherwise insert into message
                        if state.trimmedText.isEmpty {
                            model.sendReaction(emoji: emoji, hasPremium: hasPremium)
                            HapticManager.impact(.light)
                        } else {
                            state.insertAtCursor(emoji)
                        }
                    },
                    onPremiumUpsell: {
                        // Don't silently close — switch to free pack so user can still pick
                        if let freeIdx = emojiPacks.firstIndex(where: { !$0.isPremium }) {
                            currentPackIndex = freeIdx
                        }
                        HapticManager.impact(.light)
                    },
                    onSwitchPack: { index in
                        currentPackIndex = index
                    },
                    packs: emojiPacks
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Telegram-style: [ field ………………… ] [😊] [↑]
            HStack(alignment: .bottom, spacing: 8) {
                VStack(spacing: 4) {
                    TextField("Сообщение…", text: $state.text, axis: .vertical)
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
                        .onTapGesture {
                            if showEmojiPanel {
                                withAnimation(.easeOut(duration: 0.2)) { showEmojiPanel = false }
                            }
                        }

                    if state.isOverLength {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("\(state.trimmedText.count)/\(ChatComposerState.maxLength)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Cinema2026.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                }

                // Emoji — right side next to send (Telegram)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showEmojiPanel.toggle()
                    }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(showEmojiPanel ? Cinema2026.accent : Cinema2026.secondary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Эмодзи")
                .onLongPressGesture {
                    showPacksPopover = true
                }
                .popover(isPresented: $showPacksPopover) {
                    PacksPopover(
                        packs: emojiPacks,
                        currentIndex: $currentPackIndex,
                        hasPremium: hasPremium,
                        onDismiss: { showPacksPopover = false }
                    )
                }

                Button {
                    let value = state.trimmedText
                    guard !value.isEmpty, !state.isOverLength else { return }
                    model.sendChat(text: value)
                    state.clearAfterSend()
                    showEmojiPanel = false
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            (!state.trimmedText.isEmpty && !state.isOverLength)
                                ? AnyShapeStyle(Cinema2026.accentAction)
                                : AnyShapeStyle(Cinema2026.raised),
                            in: Circle()
                        )
                        .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
                }
                .disabled(state.trimmedText.isEmpty || state.isOverLength)
                .accessibilityLabel("Отправить")
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
                    .foregroundStyle(Cinema2026.secondary)
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

// Helper to load custom PNG/GIF emoji from bundle Resources/Emojis/<pack>/
// Supports both SF Symbol renders (Reactions, Plink+, Fun packs)
// and custom art (Cute Faces, Pepe, Stickers, Cats, Le Pepe packs).
struct EmojiAssetImage: View {
    let name: String
    let pack: String

    @State private var gifFrames: [UIImage] = []
    @State private var gifLoaded = false

    var body: some View {
        Group {
            if let uiImage = loadStaticImage() {
                Image(uiImage: uiImage)
                    .resizable()
            } else if !gifFrames.isEmpty {
                GifPlayerView(images: gifFrames)
            } else {
                // Fallback to SF Symbol
                Image(systemName: "face.smiling")
                    .resizable()
            }
        }
        .onAppear { loadGifIfNeeded() }
    }

    private func packDir() -> String {
        PlinkEmojiCatalog.packDirectory(for: pack)
    }

    private func loadStaticImage() -> UIImage? {
        // Try PNG first
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Emojis/\(packDir())"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            return img
        }
        // Try Assets.xcassets (for new custom packs)
        if let img = UIImage(named: name, in: .main, with: nil) {
            return img
        }
        return nil
    }

    private func loadGifIfNeeded() {
        guard !gifLoaded else { return }
        gifLoaded = true

        // Try GIF
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif", subdirectory: "Emojis/\(packDir())"),
              let data = try? Data(contentsOf: url) else {
            return
        }
        gifFrames = decodeGif(data)
    }

    private func decodeGif(_ data: Data) -> [UIImage] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: cgImage))
            }
        }
        return images
    }
}

// Simple GIF player — cycles through frames
struct GifPlayerView: View {
    let images: [UIImage]
    @State private var currentFrame = 0
    private let frameDuration: TimeInterval = 0.1

    var body: some View {
        if images.isEmpty {
            Color.clear
        } else {
            Image(uiImage: images[currentFrame])
                .resizable()
                .onAppear {
                    Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { _ in
                        currentFrame = (currentFrame + 1) % images.count
                    }
                }
        }
    }
}
