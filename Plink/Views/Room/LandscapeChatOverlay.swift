import SwiftUI

// MARK: - Smart Landscape Overlay (Блок 2 — горизонтальный чат поверх видео)
/// Полноэкранный ландшафтный режим: видеоплеер на весь экран, чат ОСТАЁТСЯ
/// доступным в правой трети экрана с ultraThinMaterial подложкой.
///
/// Жесты:
/// - Swipe-to-collapse: панель чата смахивается вправо к краю.
/// - Тап по стрелочке возвращает чат с пружинной анимацией.
///
/// Читаемость:
/// - Текст белый + плотная тень (.chatTextShadow()) для чтения на любых сценах.
/// - Поле ввода закреплено внизу, поднимается с клавиатурой.
struct LandscapeChatOverlay: View {
    let messages: [ChatMessage]
    @Binding var chatText: String
    var onSend: () -> Void

    /// Управление сворачиванием (управляется жестом swipe).
    @Binding var isCollapsed: Bool

    /// Смещение панели при драге (до завершения жеста).
    @State private var dragOffset: CGFloat = 0
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width / 3.2  // правая треть экрана

            ZStack(alignment: .trailing) {
                // ── Чат-панель ──────────────────────────────────────
                if !isCollapsed {
                    chatPanel(width: panelWidth, height: geo.size.height)
                        .offset(x: dragOffset)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // ── Стрелочка для разворачивания ────────────────────
                if isCollapsed {
                    expandButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isCollapsed)
        }
    }

    // MARK: - Chat Panel

    private func chatPanel(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Заголовок + кнопка свернуть
            HStack {
                Text(loc.string(.roomChat))
                    .font(.caption.bold())
                    .foregroundColor(.raveTextPrimary)
                    .chatTextShadow()
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        isCollapsed = true
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.raveTextPrimary)
                        .chatTextShadow()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Лента сообщений
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(messages) { message in
                            LandscapeChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastID = messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Компактное поле ввода
            HStack(spacing: 8) {
                TextField(loc.string(.roomMessagePlaceholder), text: $chatText)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .onSubmit { onSend() }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.body)
                        .foregroundColor(chatText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .gray : .raveAccent)
                }
                .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: width, height: height)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // ── Жест сворачивания (Swipe-to-Collapse вправо) ─────────
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // тянем только вправо (положительное смещение)
                    if value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 80
                    if value.translation.width > threshold {
                        // Смахнули достаточно — сворачиваем
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isCollapsed = true
                            dragOffset = 0
                        }
                    } else {
                        // Возвращаем обратно
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - Expand Button

    private var expandButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isCollapsed = false
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 28, height: 60)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(.trailing, 8)
    }
}

// MARK: - Landscape Chat Bubble
private struct LandscapeChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.raveAccent)
                    .chatTextShadow()
                Text(message.text)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .chatTextShadow()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview
#Preview("Landscape Chat") {
    LandscapeChatOverlay(
        messages: [
            .preview,
            ChatMessage(
                id: "m2", roomID: "r1", senderID: "u2",
                senderName: "Jordan", text: "This is 🔥🔥🔥",
                timestamp: .now, isRead: true,
                senderAvatarURL: nil
            ),
        ],
        chatText: .constant(""),
        onSend: {},
        isCollapsed: .constant(false)
    )
    .background(Color.black)
}
