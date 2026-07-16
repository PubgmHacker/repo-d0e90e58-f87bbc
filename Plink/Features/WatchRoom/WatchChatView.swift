// Plink/Features/WatchRoom/WatchChatView.swift — PATCH 02 polish + P0 report/block/kick

import SwiftUI

struct WatchChatView: View {
    let model: WatchRoomModel
    @State private var atBottom = true
    @State private var reportTarget: ChatMessageInfo?
    @State private var blockTarget: ChatMessageInfo?
    @State private var kickTarget: ChatMessageInfo?
    @State private var toast: String?

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.chatMessages.filter { !UserBlockManager.shared.isBlocked($0.senderId) }) { message in
                        WatchChatBubbleInline(
                            message: message,
                            isOwn: message.senderId == model.currentUserId,
                            onRetry: { model.retryChatMessage(message) }
                        )
                        .id(message.id)
                        .contextMenu {
                            if message.senderId != model.currentUserId {
                                Button {
                                    reportTarget = message
                                } label: {
                                    Label("Пожаловаться", systemImage: "flag")
                                }
                                Button(role: .destructive) {
                                    blockTarget = message
                                } label: {
                                    Label("Заблокировать", systemImage: "hand.raised")
                                }
                                if model.isHost {
                                    Button(role: .destructive) {
                                        kickTarget = message
                                    } label: {
                                        Label("Кикнуть", systemImage: "person.badge.minus")
                                    }
                                }
                            }
                            Button {
                                UIPasteboard.general.string = message.text
                            } label: {
                                Label("Копировать", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .background(
                ZStack {
                    // Room theme from Оформление → Темы комнат
                    PremiumStatusManager.shared.selectedRoomTheme.chatBackground
                        .opacity(0.92)
                    Cinema2026.background.opacity(0.18)
                }
                .ignoresSafeArea()
            )
            .onChange(of: model.chatMessages.count) { _, _ in
                guard atBottom, let last = model.chatMessages.last else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    reader.scrollTo(last.id, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom && model.unreadCount > 0 {
                    Button {
                        if let last = model.chatMessages.last {
                            withAnimation(.easeOut(duration: 0.22)) {
                                reader.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(model.unreadCount)")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Cinema2026.text)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .accessibilityLabel("Scroll to latest message")
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Cinema2026.surface.opacity(0.95), in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .sheet(item: $reportTarget) { message in
            ChatReportSheet(
                senderName: message.senderName,
                onSubmit: { reason in
                    Task {
                        do {
                            try await UserBlockManager.shared.report(
                                targetUserId: message.senderId,
                                roomId: model.roomId,
                                messageId: message.messageId,
                                reason: reason
                            )
                            showToast("Жалоба отправлена")
                        } catch {
                            showToast("Не удалось отправить жалобу")
                        }
                        reportTarget = nil
                    }
                },
                onCancel: { reportTarget = nil }
            )
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Заблокировать \(blockTarget?.senderName ?? "")?",
            isPresented: Binding(
                get: { blockTarget != nil },
                set: { if !$0 { blockTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Заблокировать", role: .destructive) {
                if let t = blockTarget {
                    UserBlockManager.shared.blockUser(t.senderId)
                    showToast("Пользователь заблокирован")
                }
                blockTarget = nil
            }
            Button("Отмена", role: .cancel) { blockTarget = nil }
        } message: {
            Text("Сообщения от этого пользователя будут скрыты.")
        }
        .confirmationDialog(
            "Кикнуть \(kickTarget?.senderName ?? "")?",
            isPresented: Binding(
                get: { kickTarget != nil },
                set: { if !$0 { kickTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Кикнуть", role: .destructive) {
                if let t = kickTarget {
                    Task {
                        let ok = await model.kickParticipant(userId: t.senderId)
                        showToast(ok ? "Участник удалён" : "Не удалось кикнуть")
                    }
                }
                kickTarget = nil
            }
            Button("Отмена", role: .cancel) { kickTarget = nil }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Report sheet

private struct ChatReportSheet: View {
    let senderName: String
    let onSubmit: (ReportReason) -> Void
    let onCancel: () -> Void
    @State private var selected: ReportReason = .spam

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Жалоба на \(senderName)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Text("Выберите причину. Модераторы рассмотрят обращение.")
                    .font(.system(size: 14))
                    .foregroundStyle(Cinema2026.secondary)

                ForEach(ReportReason.allCases) { reason in
                    Button {
                        selected = reason
                    } label: {
                        HStack {
                            Image(systemName: selected == reason ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected == reason ? Cinema2026.accent : Cinema2026.secondary)
                            Text(reason.rawValue)
                                .foregroundStyle(Cinema2026.text)
                            Spacer()
                        }
                        .padding(12)
                        .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reason.rawValue)
                }

                Spacer()

                Button {
                    onSubmit(selected)
                } label: {
                    Text("Отправить жалобу")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Cinema2026.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onCancel)
                }
            }
        }
    }
}

// MARK: - WatchChatBubbleInline (V5 — replaces deleted WatchChatBubble.swift)

private struct WatchChatBubbleInline: View {
    let message: ChatMessageInfo
    let isOwn: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn { Spacer(minLength: 56) }
            if !isOwn { ChatAvatarInline(message: message) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn {
                    HStack(spacing: 4) {
                        if message.isAdmin {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Cinema2026.amber)
                        }
                        if message.isPremium {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Cinema2026.accent)
                        }
                        Text(message.senderName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(roleColor)
                    }
                }

                PlinkMessageBubble(
                    text: message.text,
                    isOwn: isOwn,
                    styleID: isOwn ? PlinkBubbleStylePrefs.currentID : nil,
                    fontSize: 15
                )

                if message.isPending {
                    Text("Sending…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Cinema2026.secondary)
                } else if message.isFailed {
                    Button(action: onRetry) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Cinema2026.danger)
                    }
                }
            }

            if isOwn { ChatAvatarInline(message: message) }
            if !isOwn { Spacer(minLength: 56) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isOwn ? "Вы" : message.senderName): \(message.text)")
        .accessibilityHint(isOwn ? "" : "Удерживайте для жалобы или блокировки")
    }

    private var roleColor: Color {
        if message.isAdmin { return Cinema2026.amber }
        if message.isPremium { return Cinema2026.accent }
        return Cinema2026.secondary
    }
}

private struct ChatAvatarInline: View {
    let message: ChatMessageInfo

    private var letter: String {
        PlinkAvatarURL.letter(from: message.senderName)
    }

    private var avatarURL: URL? {
        // Bind strictly to this message's sender — never current user
        PlinkAvatarURL.resolve(userId: message.senderId, stored: nil)
    }

    var body: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        letterCircle
                    }
                }
            } else {
                letterCircle
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var letterCircle: some View {
        Circle()
            .fill(Cinema2026.accent.opacity(0.25))
            .overlay(
                Text(letter)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - V5WatchBubbleShape

private struct V5WatchBubbleShape: Shape {
    let isOwn: Bool
    func path(in rect: CGRect) -> Path {
        let radii = RectangleCornerRadii(
            topLeading: isOwn ? 16 : 6,
            bottomLeading: 16,
            bottomTrailing: 16,
            topTrailing: isOwn ? 6 : 16
        )
        return Path(roundedRect: rect, cornerRadii: radii)
    }
}
