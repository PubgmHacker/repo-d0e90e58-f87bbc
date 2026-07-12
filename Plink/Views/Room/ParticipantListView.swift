import SwiftUI

// MARK: - Participant List View (Premium)
/// 🔧 REDESIGNED: Full premium redesign with:
///   • Russian localization
///   • Glass cards (ultraThinMaterial)
///   • User IDs shown in small monospaced font
///   • Host badge + online indicator
///   • Copy room code + share
///   • Proper section headers
struct ParticipantListView: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // ── Room Info Card ──
                        roomInfoCard

                        // ── Participants Section ──
                        PlinkSectionHeader(text: "В комнате (\(room.participantCount)/\(room.maxParticipants))")
                            .padding(.horizontal, 16)

                        PlinkSettingsCard {
                            // Host first
                            if let host = room.participants.first(where: { $0.id == room.hostID }) {
                                participantRow(host, isHost: true)
                                if room.participants.count > 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                        .padding(.leading, 56)
                                }
                            }

                            // Other participants
                            ForEach(Array(room.participants.filter { $0.id != room.hostID }.enumerated()), id: \.element.id) { index, user in
                                participantRow(user, isHost: false)
                                if index < room.participants.filter({ $0.id != room.hostID }).count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                        .padding(.leading, 56)
                                }
                            }

                            // Empty state
                            if room.participants.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.2.slash")
                                            .font(.system(size: 28))
                                            .foregroundColor(Cinema2026.tertiary)
                                        Text("Нет участников")
                                            .font(.system(size: 14))
                                            .foregroundColor(Cinema2026.tertiary)
                                    }
                                    .padding(.vertical, 24)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Участники")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Cinema2026.accent)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Room Info Card

    private var roomInfoCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Room icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Cinema2026.accent.opacity(0.2), Cinema2026.accent.opacity(0.15)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "rectangle.stack.fill.badge.play")
                        .font(.system(size: 20))
                        .foregroundColor(Cinema2026.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Cinema2026.text)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Room code
                        HStack(spacing: 4) {
                            Text("Код:")
                                .font(.system(size: 11))
                                .foregroundColor(Cinema2026.tertiary)
                            Text(room.code)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(Cinema2026.accent)
                        }

                        // Copy button
                        Button {
                            HapticManager.impact(.light)
                            UIPasteboard.general.string = room.code
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(Cinema2026.tertiary)
                        }
                    }
                }

                Spacer()

                // Participant count badge
                VStack(spacing: 2) {
                    Text("\(room.participantCount)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(Cinema2026.text)
                    Text("/ \(room.maxParticipants)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Cinema2026.tertiary)
                }
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(14)

            // 🔧 Share room button
            Divider().background(Color.white.opacity(0.06))

            Button {
                HapticManager.impact(.light)
                UIPasteboard.general.string = "Присоединяйся к комнате \(room.name) в Плинк! Код: \(room.code)"
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                    Text("Поделиться кодом комнаты")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Cinema2026.tertiary)
                }
                .foregroundColor(Cinema2026.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Participant Row

    @ViewBuilder
    private func participantRow(_ user: UserPreview, isHost: Bool) -> some View {
        HStack(spacing: 12) {
            // Avatar with online indicator
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isHost
                                ? [Cinema2026.accent.opacity(0.6), Cinema2026.accent.opacity(0.4)]
                                : [Cinema2026.accent.opacity(0.3), Cinema2026.accent.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(user.username.prefix(1).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )

                // Online dot
                Circle()
                    .fill(user.isOnline ? Cinema2026.accent : Cinema2026.tertiary.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Cinema2026.background, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Cinema2026.text)

                    if isHost {
                        Text("ХОСТ")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Cinema2026.accent.opacity(0.3))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Cinema2026.accent.opacity(0.5), lineWidth: 0.5))
                    }

                    // 🔧 User ID (small, monospaced)
                    Text("#\(String(user.id.suffix(8)))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Cinema2026.tertiary)
                }

                Text(user.isOnline ? "В сети" : "Не в сети")
                    .font(.system(size: 11))
                    .foregroundColor(user.isOnline ? Cinema2026.accent : Cinema2026.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
