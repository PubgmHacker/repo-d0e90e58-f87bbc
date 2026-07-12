import SwiftUI

// MARK: - Chat View (с UGC-модерацией — Блок 1)
/// In-room text chat overlay. Messages sent via WebSocket, displayed in real-time.
///
/// UGC (Блок 1): каждое сообщение имеет контекстное меню
/// «Пожаловаться» (Report) и «Заблокировать» (Block).
/// Заблокированные пользователи мгновенно фильтруются локально.
struct ChatView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let messages: [ChatMessage]
    @Binding var chatText: String
    var onSend: () -> Void

    // UGC-модерация (Блок 1)
    var onReport: ((ChatMessage) -> Void)?
    var onBlock: ((ChatMessage) -> Void)?

    // Состояние контекстного меню
    @State private var reportTarget: ChatMessage?
    @State private var blockTarget: ChatMessage?

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                        .contextMenu {
                                            Button {
                                                reportTarget = message
                                            } label: {
                                                Label(loc.string(.chatReport), systemImage: "flag")
                                            }

                                            Button(role: .destructive) {
                                                blockTarget = message
                                            } label: {
                                                Label(loc.string(.chatBlock), systemImage: "hand.raised")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastID = messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                    }

                    Divider()
                        .background(Color.raveSurface)

                    HStack(spacing: 10) {
                        TextField(loc.string(.chatPlaceholder), text: $chatText)
                            .textFieldStyle(RaveTextFieldStyle())
                            .onSubmit { onSend() }

                        Button(action: onSend) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(chatText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? .raveSurface : .ravePrimary)
                        }
                        .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle(loc.string(.chatTitle))
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
        // ── Alert: Пожаловаться ──────────────────────────────────
        .alert(loc.string(.chatReportTitle), isPresented: Binding(
            get: { reportTarget != nil },
            set: { if !$0 { reportTarget = nil } }
        )) {
            Button(loc.string(.cancel), role: .cancel) { reportTarget = nil }
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) {
                    if let target = reportTarget {
                        onReport?(target)
                    }
                    reportTarget = nil
                }
            }
        } message: {
            Text(loc.string(.chatReportMessage))
        }
        // ── Alert: Заблокировать ─────────────────────────────────
        .alert(loc.string(.chatBlockTitle), isPresented: Binding(
            get: { blockTarget != nil },
            set: { if !$0 { blockTarget = nil } }
        )) {
            Button(loc.string(.cancel), role: .cancel) { blockTarget = nil }
            Button(loc.string(.chatBlock), role: .destructive) {
                if let target = blockTarget {
                    onBlock?(target)
                }
                blockTarget = nil
            }
        } message: {
            if let target = blockTarget {
                Text(String(format: loc.string(.chatBlockMessageWithName), target.senderName))
            }
        }
    }
}

// MARK: - Chat Bubble
private struct ChatBubble: View {
    let message: ChatMessage

    private var isOwnMessage: Bool {
        message.senderName == "You"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isOwnMessage { Spacer(minLength: 40) }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                if !isOwnMessage {
                    Text(message.senderName)
                        .font(.caption2.bold())
                        .foregroundColor(.raveSecondary)
                        .padding(.leading, 4)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(isOwnMessage ? .white : .raveTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOwnMessage ? Color.ravePrimary : Color.raveCard)
                    .clipShape(ChatBubbleShape(isOwn: isOwnMessage))

                Text(message.timeString)
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary.opacity(0.6))
                    .padding(.trailing, 4)
            }
        }
    }
}

// MARK: - Chat Bubble Shape
private struct ChatBubbleShape: Shape {
    let isOwn: Bool

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight, isOwn ? .bottomLeft : .bottomRight],
            cornerRadii: CGSize(width: 14, height: 14)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview
#Preview {
    ChatView(
        messages: [
            .preview,
            ChatMessage(
                id: "msg_002", roomID: "room_001", senderID: "user_002",
                senderName: "Jordan", text: "This sync is amazing! 🔥",
                timestamp: .now.addingTimeInterval(-60), isRead: true,
                senderAvatarURL: nil
            ),
        ],
        chatText: .constant(""),
        onSend: {},
        onReport: { _ in },
        onBlock: { _ in }
    )
    .preferredColorScheme(.dark)
}
