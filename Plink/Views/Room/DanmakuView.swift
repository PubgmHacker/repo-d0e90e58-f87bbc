import SwiftUI

// MARK: - Danmaku View (Блок 1 — Бегущая строка в ландшафтном режиме)
/// Потоковый чат-оверлей: сообщения летят справа налево в нижней четверти экрана.
/// Оптимизирован через GeometryReader + offset для стабильных 60+ FPS.
/// Каждый DannmakuRow имеет черную обводку текста для 100% читаемости на любом фоне.

struct DanmakuView: View {
    let messages: [ChatMessage]

    /// Максимальное кол-во одновременно видимых строк (экономия памяти).
    private let maxVisibleRows = 12

    var body: some View {
        GeometryReader { geo in
            let rowHeight: CGFloat = 28
            let bottomPadding: CGFloat = 8
            let totalRows = Int(geo.size.height / (rowHeight + 2))

            ZStack(alignment: .bottomLeading) {
                ForEach(visibleRows(totalRows), id: \.0) { index, message in
                    DanmakuRow(message: message, containerWidth: geo.size.width)
                        .frame(height: rowHeight)
                        .offset(y: -(CGFloat(index) * (rowHeight + 2)))
                        .offset(y: -bottomPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    /// Берём последние N сообщений для строк, распределяя по вертикали.
    private func visibleRows(_ maxRows: Int) -> [(Int, ChatMessage)] {
        let count = min(messages.count, min(maxRows, maxVisibleRows))
        guard count > 0 else { return [] }
        let start = messages.count - count
        let slice = messages[start..<messages.count]
        return Array(slice).enumerated().map { (offset, element) in (offset, element) }
    }
}

// MARK: - Danmaku Row
/// Одно летящее сообщение. offset анимируется от правого края до левого.
private struct DanmakuRow: View {
    let message: ChatMessage
    let containerWidth: CGFloat

    @State private var offsetX: CGFloat = 0
    @State private var appeared = false

    private let animationDuration: TimeInterval = 8.0

    var body: some View {
        HStack(spacing: 4) {
            Text(message.senderName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.raveAccent)
            Text(": \(message.text)")
                .font(.system(size: 13))
                .foregroundColor(.white)
        }
        .danmakuStroke() // черная обводка для читаемости
        .fixedSize()
        .offset(x: offsetX)
        .onAppear {
            // Ширина текста + контейнер = общая дистанция пролёта
            let textWidth = estimateWidth()
            offsetX = containerWidth
            appeared = true
            withAnimation(.linear(duration: animationDuration)) {
                offsetX = -textWidth
            }
        }
    }

    /// Приблизительная ширина текста для рассчёта анимации.
    private func estimateWidth() -> CGFloat {
        let base = CGFloat(message.senderName.count + message.text.count + 3) * 8
        return max(base, 120)
    }
}

// MARK: - Danmaku Text Stroke Modifier
/// Плотная черная тень+обводка для 100% читаемости на любом фоне видео.
extension View {
    func danmakuStroke() -> some View {
        self
            .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 0)
            .shadow(color: .black.opacity(0.7), radius: 2, x: 1, y: 1)
            .shadow(color: .black.opacity(0.5), radius: 2, x: -1, y: -1)
    }
}
