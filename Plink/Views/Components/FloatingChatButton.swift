import SwiftUI

// MARK: - Floating Chat Button (Блок 1 — Портретный чат-оверлей)
/// Прозрачная плавающая кнопка-иконка слева экрана. Нажатие открывает
/// полупрозрачную панель чата поверх видео — не уводит фокус с плеера.

struct FloatingChatButton: View {
    let unreadCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 48, height: 48)

                Image(systemName: "bubble.left.fill")
                    .font(.title3)
                    .foregroundColor(.white)

                // Badge с количеством непрочитанных
                if unreadCount > 0 {
                    Text("\(min(unreadCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.raveAccent)
                        .clipShape(Circle())
                        .offset(x: 16, y: -16)
                }
            }
        }
    }
}

// MARK: - Floating Chat Overlay (полупрозрачная панель чата поверх видео)
/// Вызывается через FloatingChatButton. Полупрозрачная, не перекрывает всё видео.
struct FloatingChatOverlay: View {
    let messages: [ChatMessage]
    @Binding var chatText: String
    let onSend: () -> Void
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Полупрозрачная подложка
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // Панель чата
            VStack(spacing: 0) {
                // Заголовок
                HStack {
                    Text("Chat")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(Color.white.opacity(0.15))

                // Сообщения
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messages) { message in
                                FloatingChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastID = messages.last?.id {
                            withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.15))

                // Поле ввода
                HStack(spacing: 10) {
                    TextField("Message...", text: $chatText)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .onSubmit { onSend() }

                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(chatText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? .gray : .ravePrimary)
                    }
                    .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.vertical, 60)
        }
        .transition(.opacity)
    }
}

// MARK: - Floating Chat Bubble
private struct FloatingChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.senderName)
                .font(.caption.bold())
                .foregroundColor(.raveAccent)

            Text(message.text)
                .font(.caption)
                .foregroundColor(.white)

            Spacer(minLength: 0)

            Text(message.timeString)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
