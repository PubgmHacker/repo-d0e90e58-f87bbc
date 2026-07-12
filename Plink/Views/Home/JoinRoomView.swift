import SwiftUI

// MARK: - JoinRoomView (Присоединиться к комнате)
/// 🔧 NEW: Full-screen join room screen with Open/Locked sections.
///
/// Open Room:
///   • Enter room code only (6 chars)
///   • No password needed
///
/// Locked Room:
///   • Enter room code AND password
///   • If password is wrong → access denied error
///
/// Both sections call RoomService.joinRoom with code + optional password.
struct JoinRoomView: View {
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    var onRoomJoined: (Room) -> Void

    @State private var selectedTab: JoinTab = .open
    @State private var roomCode = ""
    @State private var roomPassword = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    private var roomService: RoomService { RoomService(api: apiClient) }

    enum JoinTab: String, CaseIterable, Identifiable {
        case open = "open"
        case locked = "locked"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: return "Открытая"
            case .locked: return "Закрытая"
            }
        }

        var icon: String {
            switch self {
            case .open: return "lock.open"
            case .locked: return "lock.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .open: return "Только код комнаты"
            case .locked: return "Код + пароль"
            }
        }
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // ── Tab Switcher ──
                    VStack(alignment: .leading, spacing: 6) {
                        PlinkSectionHeader(text: "Тип комнаты")

                        HStack(spacing: 12) {
                            ForEach(JoinTab.allCases) { tab in
                                tabButton(tab)
                                }
                            }
                        }

                        // ── Input Fields ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: selectedTab == .open ? "Код комнаты" : "Код и пароль")

                            PlinkSettingsCard {
                                // Room code field (both tabs)
                                VStack(spacing: 0) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "number.square.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                            .frame(width: 28, height: 28)
                                            .background(Cinema2026.accent.opacity(0.18))
                                            .clipShape(RoundedRectangle(cornerRadius: 7))

                                        TextField("ABC123", text: $roomCode)
                                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                                            .foregroundColor(Cinema2026.text)
                                            .multilineTextAlignment(.leading)  // 🔧 FIX: было .center — код был по центру, пароль слева = некрасиво. Теперь оба слева.
                                            .autocapitalization(.allCharacters)
                                            .disableAutocorrection(true)
                                            .onChange(of: roomCode) { _, newValue in
                                                roomCode = String(newValue.prefix(6)).uppercased()
                                            }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)

                                    // Password field (locked tab only)
                                    if selectedTab == .locked {
                                        Divider()
                                            .background(Color.white.opacity(0.06))
                                            .padding(.leading, 56)

                                        HStack(spacing: 12) {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white)
                                                .frame(width: 28, height: 28)
                                                .background(Cinema2026.accent.opacity(0.18))
                                                .clipShape(RoundedRectangle(cornerRadius: 7))

                                            SecureField("Пароль комнаты", text: $roomPassword)
                                                .font(.system(size: 16))
                                                .foregroundColor(Cinema2026.text)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                    }
                                }
                            }
                        }

                        // ── Error ──
                        if let errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Cinema2026.danger)
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundColor(Cinema2026.danger)
                            }
                            .padding(.horizontal, 16)
                        }

                        // ── Info ──
                        Text(selectedTab == .open
                             ? "Введите 6-значный код комнаты. Открытые комнаты не требуют пароля."
                             : "Введите код комнаты и пароль. Если пароль неверный — доступ будет отказан.")
                            .font(.system(size: 11))
                            .foregroundColor(Cinema2026.tertiary)
                            .padding(.horizontal, 16)

                        Spacer(minLength: 100)  // 🔧 FIX: было 32 — кнопка зажималась, теперь 100 для запаса
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 20)  // 🔧 FIX: horizontal padding отсутствовал — контент вылезал за края
                }

            // ── Join Button (bottom) ──
            VStack {
                Spacer()
                joinButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(_ tab: JoinTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(tab.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Cinema2026.tertiary)
            }
            .foregroundColor(isSelected ? Cinema2026.text : Cinema2026.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            // 🔧 TELEGRAM-GLASS: убран cyan raveGradient. Теперь прозрачное стекло
            // с металлик-обводкой. Active отличается только белым текстом.
            .telegramGlass(
                cornerRadius: 14,
                borderColor: isSelected ? .black.opacity(0.6) : .black.opacity(0.4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Join Button

    private var joinButton: some View {
        Button {
            joinRoom()
        } label: {
            HStack(spacing: 10) {
                if isJoining {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18))
                }
                Text(isJoining ? "Подключение…" : "Присоединиться")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            // 🔧 TELEGRAM-GLASS: убран cyan raveGradient + glow. Теперь прозрачное
            // стекло с металлик-обводкой. Текст белый = контраст на тёмном стекле.
            .telegramGlass(cornerRadius: 16, borderColor: .black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!canJoin || isJoining)
        .opacity(canJoin && !isJoining ? 1 : 0.5)
    }

    private var canJoin: Bool {
        let codeValid = roomCode.count == 6
        if selectedTab == .open {
            return codeValid
        } else {
            return codeValid && !roomPassword.isEmpty
        }
    }

    // MARK: - Join Action

    private func joinRoom() {
        guard canJoin else { return }

        isJoining = true
        errorMessage = nil
        HapticManager.impact(.medium)

        Task {
            do {
                let room = try await roomService.joinRoom(code: roomCode, password: selectedTab == .locked ? roomPassword : nil)
                await MainActor.run {
                    isJoining = false
                    HapticManager.roomJoined()
                    onRoomJoined(room)
                }
            } catch APIError.unauthorized {
                await MainActor.run {
                    isJoining = false
                    errorMessage = "Неверный пароль или код комнаты"
                    HapticManager.impact(.heavy)
                }
            } catch APIError.notFound {
                await MainActor.run {
                    isJoining = false
                    errorMessage = "Комната не найдена. Проверьте код."
                    HapticManager.impact(.heavy)
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = "Ошибка: \(error.localizedDescription)"
                    HapticManager.impact(.heavy)
                }
            }
        }
    }
}
