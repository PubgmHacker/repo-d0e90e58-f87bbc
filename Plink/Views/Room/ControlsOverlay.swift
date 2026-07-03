import SwiftUI

// MARK: - Controls Overlay v2 (YouTube-style)
/// Кнопки управления по центру видео. Появляются по тапу, скрываются через 3с.
///
/// Структура:
/// - Сверху: название комнаты, аватары участников, кнопка закрыть
/// - Центр: play/pause (большая), seek ±10
/// - Снизу: ползунок времени + тайминги
struct ControlsOverlay: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let participantCount: Int
    let roomName: String
    let isFullscreen: Bool

    var onTogglePlay: () -> Void
    var onSeek: (TimeInterval) -> Void
    var onSeekRelative: (TimeInterval) -> Void
    var onClose: () -> Void
    var onShowParticipants: () -> Void
    var onToggleFullscreen: () -> Void

    @Binding var isVisible: Bool

    var body: some View {
        ZStack {
            // Тёмный gradient для читаемости (появляется с контролами)
            LinearGradient(
                colors: [
                    .black.opacity(0.5),
                    .clear,
                    .black.opacity(0.5),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(isVisible ? 1 : 0)

            VStack {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .opacity(isVisible ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .allowsHitTesting(isVisible)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Text(roomName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            ParticipantAvatars(count: participantCount, onTap: onShowParticipants)
        }
    }

    // MARK: - Center Controls (YouTube-style)

    private var centerControls: some View {
        HStack(spacing: 32) {
            Button(action: { onSeekRelative(-10) }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Button(action: { onSeekRelative(10) }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Bottom Bar (seek + time + fullscreen)

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(formattedTime(currentTime))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.white.opacity(0.8))

            SeekBar(
                progress: duration > 0 ? currentTime / duration : 0,
                onSeek: { ratio in onSeek(ratio * duration) }
            )

            Text(formattedTime(duration))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.white.opacity(0.8))

            // YouTube-style fullscreen toggle (правый нижний угол)
            Button(action: onToggleFullscreen) {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left"
                                               : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func formattedTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Seek Bar

private struct SeekBar: View {
    let progress: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * progress, height: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .offset(x: geo.size.width * progress - 7)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        onSeek(ratio)
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Participant Avatars

private struct ParticipantAvatars: View {
    let count: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: -6) {
                ForEach(0..<min(count, 4), id: \.self) { i in
                    Circle()
                        .fill(Color(hue: Double(i) / 4.0, saturation: 0.6, brightness: 0.8))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                }
                if count > 4 {
                    Text("+\(count - 4)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                }
            }
        }
    }
}
