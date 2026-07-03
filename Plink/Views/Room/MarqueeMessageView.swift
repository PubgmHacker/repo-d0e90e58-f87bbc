import SwiftUI

// MARK: - Marquee Message View
/// Бегущая строка с именем отправителя поверх видео (как в Rave/Niconico).
/// Появляется с fade, исчезает через 2.5с. Если имя + сообщение длинные —
/// анимация горизонтального сдвига (marquee). Если короткие — статично.
struct MarqueeMessageView: View {
    let senderName: String
    let text: String

    @State private var animateOffset = false
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private let displayDuration: Double = 2.5

    var body: some View {
        GeometryReader { geo in
            let fullWidth = formattedText.width(usingFont: .systemFont(ofSize: 13, weight: .medium))
            let needsMarquee = fullWidth > geo.size.width - 40
            let scrollDistance = needsMarquee ? fullWidth - geo.size.width + 60 : CGFloat(0)

            HStack(spacing: 0) {
                Text(formattedText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.black.opacity(0.5))
                    )
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .offset(x: needsMarquee ? (animateOffset ? -scrollDistance : 0) : 0)
                    .onAppear {
                        if needsMarquee {
                            withAnimation(.easeInOut(duration: displayDuration - 0.5)) {
                                animateOffset = true
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 32)
    }

    private var formattedText: String {
        "\(senderName): \(text)"
    }
}

// MARK: - String Width Extension

private extension String {
    func width(usingFont font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (self as NSString).size(withAttributes: attributes).width
    }
}

// MARK: - Marquee Container

/// Менеджер бегущих строк: показывает последнее сообщение поверх видео.
struct MarqueeContainer: View {
    let messages: [ChatMessage]

    @State private var currentMarquee: ChatMessage?
    @State private var dismissTask: Task<Void, Never>?

    private let marqueeDisplayTime: UInt64 = 2_500_000_000

    var body: some View {
        VStack {
            Spacer()
            if let msg = currentMarquee {
                MarqueeMessageView(senderName: msg.senderName, text: msg.text)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(msg.id)
            }
        }
        .onChange(of: messages.last?.id) { _, _ in
            showLatestMarquee()
        }
    }

    private func showLatestMarquee() {
        guard let last = messages.last else { return }
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentMarquee = last
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: marqueeDisplayTime)
            await MainActor.run {
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.3)) {
                        currentMarquee = nil
                    }
                }
            }
        }
    }
}
