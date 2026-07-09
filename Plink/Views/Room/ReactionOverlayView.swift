import SwiftUI

// MARK: - Reaction Overlay (Блок 3 — быстрые реакции в стиле Telegram)
/// Оверлей анимированных эмодзи, летящих снизу вверх поверх видео.
///
/// Логика:
/// - При тапе эмодзи летит снизу вверх, меняя opacity (1.0 → 0.0).
/// - Случайное смещение по X — каждое эмодзи своим путём.
/// - Время жизни объекта — 2 секунды, после автоудаление (экономия памяти).
/// - Анимацию видят все участники комнаты через WebSocket.
struct ReactionOverlayView: View {
    let reactions: [ReactionEvent]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ForEach(reactions) { reaction in
                    FlyingReaction(reaction: reaction, screenHeight: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false) // реакции не перехватывают тапы по видео
        }
    }
}

// MARK: - Flying Reaction (одно летящее эмодзи)
private struct FlyingReaction: View {
    let reaction: ReactionEvent
    let screenHeight: CGFloat

    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 4) {
            Text(reaction.emoji)
                .font(.system(size: 36))

            if let name = reaction.senderName {
                Text(name)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .chatTextShadow()
            }
        }
        .offset(
            x: hasAppeared ? reaction.horizontalOffset : 0,
            y: hasAppeared ? -screenHeight * 0.85 : 0  // летит снизу вверх
        )
        .opacity(hasAppeared ? 0 : 1.0)
        .scaleEffect(hasAppeared ? 1.4 : 0.4)
        .onAppear {
            withAnimation(.easeOut(duration: 2.0)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Reaction Bar (панель быстрых эмодзи)
/// Панель 🔥 ❤️ 😂 👍 — доступна в портретном и ландшафтном режимах.
struct ReactionBar: View {
    var onReaction: (String) -> Void

    private let emojis = ["🔥", "❤️", "😂", "👍"]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(emojis, id: \.self) { emoji in
                ReactionButton(emoji: emoji) {
                    HapticManager.impact(.light)
                    onReaction(emoji)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Reaction Button (одно эмодзи с bounce-анимацией)
private struct ReactionButton: View {
    let emoji: String
    let action: () -> Void

    @State private var isBouncing = false

    var body: some View {
        Button(action: {
            // bounce-эффект при тапе
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                isBouncing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isBouncing = false
                }
            }
            action()
        }) {
            Text(emoji)
                .font(.system(size: 26))
                .scaleEffect(isBouncing ? 1.4 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
#Preview("Reaction Bar") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ReactionBar { _ in }
                .padding(.bottom, 40)
        }
    }
}

#Preview("Flying Reactions") {
    ReactionOverlayView(reactions: [
        ReactionEvent(emoji: "🔥", senderName: "Alex"),
        ReactionEvent(emoji: "❤️", senderName: "Jordan"),
    ])
    .background(Color.black)
}
