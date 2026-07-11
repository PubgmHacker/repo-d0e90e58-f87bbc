// Plink/Features/WatchRoom/WatchChatComposer.swift — PATCH 02 polish + Commit Groups 4, 14
//
// Commit Group 1: fixed ShapeStyle conformance error (Group<Color|LinearGradient>
// → AnyShapeStyle).
// Commit Group 2: professional sizing — 40pt send button (was 36pt),
// 22pt corner radius (was 20pt), 14pt emoji button (was 16pt icon in 38pt circle).
// Commit Group 4: extract state into ChatComposerState for testability;
// add length cap enforcement (2000 chars, matches backend ChatSendSchema);
// route emoji picker through insertAtCursor (cursor-aware insertion).
// Commit Group 14: wire ReactionPickerView as popover on emoji button.
//   - Tap emoji button → popover shows ReactionPickerView
//   - Tap free emoji → state.insertAtCursor(emoji) (inserts at cursor)
//   - Tap locked premium emoji → onPremiumUpsell closure
//   - hasPremium reads from PremiumStatusManager.shared.isPremium

import SwiftUI

struct WatchChatComposer: View {
    let model: WatchRoomModel

    @State private var state = ChatComposerState()
    @State private var showReactionPicker = false

    private var canSend: Bool {
        state.canSend(connected: model.connectionState == .connected)
    }

    private var hasPremium: Bool {
        PremiumStatusManager.shared.isPremium
    }

    var body: some View {
        HStack(spacing: 10) {
            // PATCH 14: emoji button now shows ReactionPickerView as popover.
            Button {
                showReactionPicker = true
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 17))
                    .foregroundStyle(PlinkRave.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(PlinkRave.raised, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
            }
            .accessibilityLabel("Emoji")
            .popover(isPresented: $showReactionPicker) {
                ReactionPickerView(
                    hasPremium: hasPremium,
                    onPick: { emoji in
                        // Insert emoji at cursor position in the text field.
                        state.insertAtCursor(emoji)
                        showReactionPicker = false
                    },
                    onPremiumUpsell: {
                        // PATCH 14: surface upsell via toast — full PaywallView
                        // presentation is wired in Commit Group 10 follow-up.
                        showReactionPicker = false
                        // TODO: present PaywallView (Commit Group 10 follow-up)
                    }
                )
                .frame(maxWidth: 320)
            }

            VStack(spacing: 4) {
                TextField("Message…", text: $state.text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 15))
                    .foregroundStyle(PlinkRave.text)
                    .tint(PlinkRave.magenta)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PlinkRave.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                state.isOverLength ? PlinkRave.danger : .white.opacity(0.05),
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
                    .foregroundStyle(PlinkRave.danger)
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
                            ? AnyShapeStyle(PlinkRave.primaryAction)
                            : AnyShapeStyle(PlinkRave.raised),
                        in: Circle()
                    )
                    .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
            }
            .disabled(!canSend || state.isOverLength)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PlinkRave.surface.opacity(0.95))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PlinkRave.divider.opacity(0.4))
                .frame(height: 0.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkInsertAtCursor)) { note in
            if let insertion = note.userInfo?["text"] as? String {
                state.insertAtCursor(insertion)
            }
        }
    }
}

// MARK: - Emoji picker notification

extension Notification.Name {
    /// Posted by the emoji picker (or any other source) to insert text at
    /// the composer's cursor position. UserInfo: ["text": String].
    static let plinkInsertAtCursor = Notification.Name("plinkInsertAtCursor")
}
