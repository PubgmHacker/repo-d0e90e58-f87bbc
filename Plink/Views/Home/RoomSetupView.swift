import SwiftUI

// MARK: - RoomSetupView
/// 🔧 NEW: Room setup screen — final step before creating a room.
///
/// Flow: Service → ServiceBrowserView (user picks content) → RoomSetupView
///       → Room created.
///
/// User configures:
///   - Room name (auto-filled from the page title)
///   - Privacy (public / friends-only / private)
///   - Max participants (4 free / 50 premium)
///   - Content URL (from the browser, read-only)
struct RoomSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let service: VideoService
    let contentURL: String
    let contentTitle: String
    var onRoomCreated: (Room) -> Void

    @State private var roomName = ""
    @State private var privacy: RoomPrivacy = .publicRoom
    @State private var maxParticipants = 10
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let isPremium = PremiumStatusManager.shared.isPremium
    private let freeMaxParticipants = 4
    private let premiumMaxParticipants = 50

    var body: some View {
        NavigationStack {
            ZStack {
                BioluminescentBackground(energy: 0.4, dimming: 0)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // ── Content Preview Card ──
                        contentPreviewCard

                        // ── Room Name Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Название комнаты")
                            VStack(spacing: 0) {
                                TextField("Название комнаты", text: $roomName)
                                    .font(.system(size: 16))
                                    .foregroundColor(.raveTextPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                            }
                        }

                        // ── Privacy Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Приватность")
                            PlinkSettingsCard {
                                ForEach(RoomPrivacy.allCases, id: \.self) { level in
                                    privacyRow(level)
                                    if level != RoomPrivacy.allCases.last {
                                        Divider()
                                            .background(Color.white.opacity(0.06))
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }

                        // ── Participants Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Максимум участников")
                            PlinkSettingsCard {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Color.bioCyan.opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: 7))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(maxParticipants) человек")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.raveTextPrimary)
                                        Text(isPremium ? "Премиум: до \(premiumMaxParticipants)" : "Бесплатно: до \(freeMaxParticipants)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.raveTextSecondary)
                                    }

                                    Spacer()

                                    Stepper("", value: $maxParticipants,
                                            in: 2...(isPremium ? premiumMaxParticipants : freeMaxParticipants))
                                        .labelsHidden()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }

                        // ── Error ──
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundColor(.raveDanger)
                                .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }

                // ── Create Button (bottom) ──
                VStack {
                    Spacer()
                    createButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Новая комната")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.bioCyan)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Auto-fill room name from content title
            if roomName.isEmpty {
                roomName = contentTitle.isEmpty ? "Комната \(service.brandName)" : contentTitle
            }
        }
    }

    // MARK: - Content Preview Card

    private var contentPreviewCard: some View {
        HStack(spacing: 14) {
            // Service logo
            ServiceLogoView(service: service, size: 48)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(contentTitle.isEmpty ? "Выбранный контент" : contentTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(2)
                Text(service.brandName)
                    .font(.system(size: 12))
                    .foregroundColor(.raveTextSecondary)
                // Read-only URL (small, truncated)
                if let url = URL(string: contentURL) {
                    Text(url.host ?? contentURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.raveTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [Color.bioCyan.opacity(0.2), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Privacy Row

    @ViewBuilder
    private func privacyRow(_ level: RoomPrivacy) -> some View {
        Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                privacy = level
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: privacyIcon(level))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(privacyColor(level).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.raveTextPrimary)
                    Text(level.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.raveTextSecondary)
                }

                Spacer()

                // Selection checkmark
                Image(systemName: privacy == level ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(privacy == level ? .bioCyan : .raveTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func privacyIcon(_ level: RoomPrivacy) -> String {
        switch level {
        case .publicRoom:   return "globe"
        case .friendsOnly:  return "person.2.fill"
        case .privateRoom:  return "lock.fill"
        }
    }

    private func privacyColor(_ level: RoomPrivacy) -> Color {
        switch level {
        case .publicRoom:   return .bioCyan
        case .friendsOnly:  return .bioEmerald
        case .privateRoom:  return .bioTeal
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            createRoom()
        } label: {
            HStack(spacing: 10) {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                }
                Text(isCreating ? "Создание…" : "Создать комнату")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.raveGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .ravePrimary.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isCreating || roomName.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(roomName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
    }

    // MARK: - Create Room

    private func createRoom() {
        let name = roomName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "Введите название комнаты"
            return
        }

        isCreating = true
        errorMessage = nil
        HapticManager.impact(.medium)

        // Resolve real user identity (FIX C7/C8 pattern)
        let hostID: String = {
            if let data = UserDefaults.standard.data(forKey: "rave_saved_user"),
               let user = try? JSONDecoder().decode(User.self, from: data) {
                return user.id
            }
            return UUID().uuidString
        }()
        let hostName: String = {
            if let data = UserDefaults.standard.data(forKey: "rave_saved_user"),
               let user = try? JSONDecoder().decode(User.self, from: data) {
                return user.username
            }
            return "You"
        }()
        let hostIsPremium = PremiumStatusManager.shared.isPremium

        // Build MediaItem from the browsed URL
        let mediaItem = MediaItem(
            id: UUID().uuidString,
            title: contentTitle.isEmpty ? name : contentTitle,
            artist: nil,
            thumbnailURL: nil,
            streamURL: contentURL,
            duration: nil,
            mediaType: .video,
            source: .url
        )

        let room = Room(
            id: UUID().uuidString,
            name: name,
            hostID: hostID,
            hostName: hostName,
            code: generateRoomCode(),
            participants: [],
            mediaItem: mediaItem,
            isActive: true,
            maxParticipants: maxParticipants,
            hostIsPremium: hostIsPremium,
            createdAt: Date()
        )

        // Brief delay for UX (show "Создание…" state)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isCreating = false
            HapticManager.roomJoined()
            onRoomCreated(room)
        }
    }

    private func generateRoomCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
