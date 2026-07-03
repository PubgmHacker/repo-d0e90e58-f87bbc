import SwiftUI

// MARK: - Voice Chat Button (Discord-style)
/// Большая круглая кнопка микрофона по центру. Состояния:
/// - Неактивен (серый) — голосовой чат выключен
/// - Активен (зелёный, пульсирующий) — говоришь
/// - Мьют (красный) — микрофон выключен
///
/// Режим «рация» (push-to-talk) configurable в настройках.
struct VoiceChatButton: View {
    @ObservedObject var voiceChat: VoiceChatService
    var onToggle: () -> Void

    @State private var pulse = false
    @State private var ringScale: CGFloat = 1.0

    var body: some View {
        Button {
            HapticManager.impact(.medium)
            onToggle()
        } label: {
            ZStack {
                // Внешнее анимированное кольцо (индикация говорящего)
                if voiceChat.isActive && !voiceChat.isMuted {
                    Circle()
                        .stroke(Color.ravePrimary.opacity(ringScale > 1.1 ? 0.4 : 0.15), lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .scaleEffect(ringScale)
                        .opacity(ringScale > 1.1 ? 0 : 1)

                    Circle()
                        .fill(Color.ravePrimary.opacity(0.15))
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulse ? 1.15 : 1.0)
                }

                // Основной круг
                Circle()
                    .fill(buttonColor)
                    .frame(width: 48, height: 48)

                // Иконка
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(
                color: shadowColor,
                radius: voiceChat.isActive ? 12 : 4,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .onAppear { startAnimations() }
        .onChange(of: voiceChat.isActive) { _, _ in startAnimations() }
        .onChange(of: voiceChat.isMuted) { _, _ in startAnimations() }
    }

    private func startAnimations() {
        guard voiceChat.isActive && !voiceChat.isMuted else {
            pulse = false
            ringScale = 1.0
            return
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulse = true
        }
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            ringScale = 1.4
        }
    }

    private var buttonColor: Color {
        if !voiceChat.isActive { return Color.white.opacity(0.1) }
        if voiceChat.isMuted { return Color.raveDanger }
        return Color.ravePrimary
    }

    private var iconName: String {
        if !voiceChat.isActive { return "mic.slash.fill" }
        if voiceChat.isMuted { return "mic.slash.fill" }
        return "mic.fill"
    }

    private var shadowColor: Color {
        if !voiceChat.isActive { return .clear }
        if voiceChat.isMuted { return Color.raveDanger.opacity(0.4) }
        return Color.ravePrimary.opacity(0.5)
    }
}
