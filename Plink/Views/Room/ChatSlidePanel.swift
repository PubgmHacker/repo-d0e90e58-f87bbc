import SwiftUI

// MARK: - Chat Slide Panel
/// Выезжающая панель чата справа (280pt). Появляется по кнопке или свайпу
/// от правого края. НЕ сдвигает видео — перекрывает его частично с blur-фоном.
struct ChatSlidePanel: View {
    @ObservedObject private var loc = LocalizationManager.shared

    let messages: [ChatMessage]
    @Binding var chatText: String
    var onSend: () -> Void
    @Binding var isOpen: Bool

    private let panelWidth: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                // Затемнение под панелью (когда открыта)
                if isOpen {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring()) { isOpen = false } }
                        .transition(.opacity)
                }

                // Панель чата
                HStack(spacing: 0) {
                    Spacer()

                    chatContent
                        .frame(width: panelWidth)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .offset(x: isOpen ? 0 : panelWidth + 16)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: -5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            // Заголовок
            HStack {
                Text(loc.string(.roomChat))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { withAnimation(.spring()) { isOpen = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.1))

            // Лента сообщений
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastID = messages.last?.id {
                        withAnimation(.easeOut) { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Поле ввода
            HStack(spacing: 8) {
                TextField(loc.string(.roomMessagePlaceholder), text: $chatText)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .onSubmit { onSend() }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(chatText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .gray : .raveAccent)
                }
                .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.raveAccent)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
