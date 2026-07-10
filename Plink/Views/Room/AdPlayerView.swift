import SwiftUI

// MARK: - Ad Player View (Блок 2 — In-Player Ad Overlay)
/// Рекламный оверлей строго внутри фрейма видеоплеера (16:9).
/// Показывается поверх видео, НЕ на весь экран.
/// Чат, микрофоны и кнопки остаются активны.

struct AdPlayerView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let onDismiss: () -> Void
    @State private var adProgress: CGFloat = 0
    @State private var countdown: Int = 15
    /// 🔧 FIX H5: Hold a strong reference to the timer and invalidate on disappear.
    /// (was: timer created in startCountdown was held only by the run loop — if the
    /// view was dismissed before countdown finished, onDismiss was invoked ~15 times.)
    @State private var countdownTimer: Timer?

    var body: some View {
        ZStack {
            // Фон рекламы (полупрозрачный тёмный поверх видео)
            Color.black.opacity(0.85)

            VStack(spacing: 20) {
                Spacer()

                // Плашка рекламодателя
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.badge.play")
                        .font(.system(size: 36))
                        .foregroundColor(.ravePrimary)

                    Text("AD")
                        .font(.caption2.bold().monospaced())
                        .foregroundColor(.raveTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())

                    Text(loc.string(.adBreak))
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    Text(loc.string(.adBreakSubtitle))
                        .font(.caption)
                        .foregroundColor(.raveTextSecondary)
                }

                Spacer()

                // Прогресс-бар рекламы
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                            Capsule()
                                .fill(Color.ravePrimary)
                                .frame(width: geo.size.width * adProgress)
                        }
                    }
                    .frame(height: 4)

                    Text("\(countdown)s")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.raveTextSecondary)
                }
                .padding(.horizontal, 40)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            startCountdown()
        }
        // 🔧 FIX H5: Invalidate the timer when the view disappears to prevent
        // stale onDismiss() callbacks firing on a dismissed view.
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    private func startCountdown() {
        let totalSeconds = 15
        countdown = totalSeconds

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            Task { @MainActor in
                countdown -= 1
                adProgress = CGFloat(totalSeconds - countdown) / CGFloat(totalSeconds)

                if countdown <= 0 {
                    timer.invalidate()
                    onDismiss()
                }
            }
        }
    }
}
