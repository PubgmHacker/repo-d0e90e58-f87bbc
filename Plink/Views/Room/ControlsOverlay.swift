import SwiftUI

// MARK: - Controls Overlay v3 (Premium Glass)
/// 🔧 REDESIGNED: Glass-transparent controls that don't distract from the movie.
/// • Side buttons (mic, share, chat) are very subtle — low opacity glass
/// • Center controls (play/pause/seek) are prominent when visible
/// • All controls fade in/out smoothly with `isVisible`
/// • Buttons highlight on press via buttonStyle
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
            // Subtle gradient for readability (very light)
            // 🔧 v32.11: allowsHitTesting(false) — gradient must NOT catch taps.
            // Otherwise when controls are visible, tapping between buttons hits
            // the gradient instead of passing through to the transparent tap layer
            // below (which toggles showControls).
            LinearGradient(
                colors: [
                    .black.opacity(0.3),
                    .clear,
                    .black.opacity(0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)

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

    // MARK: - Top Bar (glass, very subtle)

    private var topBar: some View {
        HStack(spacing: 10) {
            glassCircleButton(icon: "chevron.down", size: 30, action: onClose)

            Text(roomName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

            Spacer()

            // 🔧 Participant count badge + avatars
            HStack(spacing: 6) {
                ParticipantBadge(count: participantCount)
                ParticipantAvatars(count: participantCount, onTap: onShowParticipants)
            }
        }
    }

    // MARK: - Center Controls (prominent when visible)

    private var centerControls: some View {
        HStack(spacing: 36) {
            glassCircleButton(
                icon: "gobackward.10",
                size: 44,
                iconSize: 20,
                action: { onSeekRelative(-10) }
            )

            // Play/pause — larger, more prominent
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(GlassButtonStyle())

            glassCircleButton(
                icon: "goforward.10",
                size: 44,
                iconSize: 20,
                action: { onSeekRelative(10) }
            )
        }
    }

    // MARK: - Bottom Bar (seek + time + fullscreen)

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(formattedTime(currentTime))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.white.opacity(0.7))

            SeekBar(
                progress: duration > 0 ? currentTime / duration : 0,
                onSeek: { ratio in onSeek(ratio * duration) }
            )

            Text(formattedTime(duration))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.white.opacity(0.7))

            glassCircleButton(
                icon: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                size: 28,
                iconSize: 12,
                action: onToggleFullscreen
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Glass Circle Button Helper

    @ViewBuilder
    private func glassCircleButton(icon: String, size: CGFloat, iconSize: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.3)
                        )
                )
        }
        .buttonStyle(GlassButtonStyle())
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

// MARK: - Glass Button Style (highlight on press)
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Seek Bar
private struct SeekBar: View {
    let progress: Double
    var onSeek: (Double) -> Void

    @State private var dragRatio: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let displayProgress = dragRatio ?? progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 3)

                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: geo.size.width * displayProgress, height: 3)

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(x: geo.size.width * displayProgress - 6)
                    .opacity(displayProgress > 0 && displayProgress < 1 ? 1 : 0)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // v32.16: live update during drag
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        dragRatio = ratio
                    }
                    .onEnded { value in
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        onSeek(ratio)
                        // Reset drag state after a short delay so the bar
                        // shows the seek result, not the drag position
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dragRatio = nil
                        }
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Participant Avatars (glass, subtle)
private struct ParticipantAvatars: View {
    let count: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: -6) {
                ForEach(0..<min(count, 4), id: \.self) { i in
                    Circle()
                        .fill(Color(hue: Double(i) / 4.0, saturation: 0.5, brightness: 0.7))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                }
                if count > 4 {
                    Text("+\(count - 4)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                }
            }
        }
    }
}
