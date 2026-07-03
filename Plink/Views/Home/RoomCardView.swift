import SwiftUI

// MARK: - Room Card View (Premium Discovery Card)
/// Карточка живой комнаты для Discovery Dashboard (Блок 1).
///
/// Спецификация:
/// - Фон: полупрозрачный тёмно-серый (#1E222B), скругление 16, тонкая граница.
/// - Слева: превью видеоконтента с ярлыком «LIVE».
/// - Справа: название, хост, статус медиа.
/// - Счётчик участников «👥 1.4k» с пульсирующей зелёной точкой.
struct RoomCardView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let room: Room

    // UGC-модерация (Блок 1)
    var onReport: ((Room) -> Void)?
    var onBlock: ((Room) -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            // ── Превью видеоконтента + LIVE-бейдж ───────────────────
            mediaThumbnail
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

            // ── Инфо о комнате ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text(room.name)
                    .font(.headline)
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)

                Text("Hosted by \(room.hostName)")
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary)

                // Статус медиа / иконка типа
                if let mediaItem = room.mediaItem {
                    HStack(spacing: 6) {
                        mediaTypeIcon(mediaItem.mediaType)
                        Text(mediaItem.displayTitle)
                            .font(.caption2)
                            .foregroundColor(.raveTextTertiary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.viewfinder")
                            .font(.caption2)
                            .foregroundColor(.raveTextTertiary)
                        Text("Waiting for media")
                            .font(.caption2)
                            .foregroundColor(.raveTextTertiary)
                    }
                }

                Spacer(minLength: 0)

                // Аватары участников (стопка)
                HStack(spacing: -6) {
                    ForEach(Array(room.participants.prefix(4).enumerated()), id: \.element.id) { index, user in
                        userAvatar(user)
                            .overlay(
                                Circle()
                                    .stroke(Color.raveCard, lineWidth: 2)
                            )
                            .zIndex(Double(4 - index))
                    }
                    if room.participantCount > 4 {
                        Text("+\(room.participantCount - 4)")
                            .font(.caption2.bold())
                            .foregroundColor(.raveTextSecondary)
                            .padding(.leading, 10)
                    }
                }
            }

            Spacer(minLength: 4)

            // ── Счётчик участников (glass badge) ──────────────────────
            ParticipantBadge(count: room.participantCount)
        }
        .padding(14)
        // ── Bioluminescent Glass: матовое стекло с неоновой подсветкой ──
        .premiumGlass(
            cornerRadius: 18,
            opacity: 0.06,
            ringColor: room.isActive
                ? LinearGradient(
                    colors: [Color.bioEmerald.opacity(0.5), Color.bioCyan.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : Color.bioNeonRing,
            glow: room.isActive
        )
        .contentShape(Rectangle())
        // UGC-модерация (Блок 1): контекстное меню
        .contextMenu {
            Button {
                onReport?(room)
            } label: {
                Label(loc.string(.chatReport), systemImage: "flag")
            }

            Button(role: .destructive) {
                onBlock?(room)
            } label: {
                Label(loc.string(.blockHost), systemImage: "hand.raised")
            }
        }
    }

    // MARK: - Media Thumbnail с LIVE-бейджем

    @ViewBuilder
    private var mediaThumbnail: some View {
        ZStack(alignment: .topLeading) {
            if let thumbnailURL = room.mediaItem?.thumbnailURL, let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderThumbnail
                    default:
                        placeholderThumbnail.shimmer()
                    }
                }
            } else {
                placeholderThumbnail
            }

            // LIVE-бейдж
            if room.isActive {
                LiveBadge()
                    .padding(6)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: room.isActive)
    }

    private var placeholderThumbnail: some View {
        ZStack {
            LinearGradient(
                colors: [Color.raveSurface.opacity(0.5), Color.raveCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: room.mediaItem == nil ? "questionmark.folder" : "play.fill")
                .font(.title2)
                .foregroundColor(.raveTextTertiary)
        }
    }

    // MARK: - Счётчик участников

    private var participantCounter: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                // Пульсирующая зелёная точка
                PulsingDot()
                Text(formattedParticipantCount)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundColor(.raveTextPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 1))
        }
    }

    /// Форматирует счётчик: 1.4k, 12.3k, и т.д.
    private var formattedParticipantCount: String {
        let count = room.participantCount
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    // MARK: - Subviews

    @ViewBuilder
    private func mediaTypeIcon(_ type: MediaItem.MediaType) -> some View {
        let (icon, color): (String, Color) = {
            switch type {
            case .movie: return ("film", .raveAccent)
            case .series: return ("tv", .raveSecondary)
            case .music: return ("music.note", .raveGreen)
            case .video: return ("video", .raveWarning)
            case .livestream: return ("dot.radiowaves.left.and.right", .raveDanger)
            }
        }()

        Image(systemName: icon)
            .font(.caption2)
            .foregroundColor(color)
    }

    @ViewBuilder
    private func userAvatar(_ user: UserPreview) -> some View {
        if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    avatarFallback(user)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
        } else {
            avatarFallback(user)
                .frame(width: 22, height: 22)
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private func avatarFallback(_ user: UserPreview) -> some View {
        Text(user.username.prefix(1).uppercased())
            .font(.caption2.bold())
            .foregroundColor(Color(hex: 0x14161C))
            .background(user.isOnline ? AnyShapeStyle(Color.ravePrimary.opacity(0.3)) : AnyShapeStyle(Color.raveSurface))
    }
}

// MARK: - Pulsing Dot
/// Плавно пульсирующая зелёная точка — индикатор живой комнаты.
struct PulsingDot: View {
    @State private var isPulsing = false

    var color: Color = .raveGreen

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing ? 2.2 : 1)
                    .opacity(isPulsing ? 0 : 0.7)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - LIVE Badge
/// Ярлык «LIVE» с красным фоном и пульсирующим свечением.
struct LiveBadge: View {
    @State private var glow = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .tracking(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.raveDanger)
        .clipShape(Capsule())
        .shadow(color: .raveDanger.opacity(glow ? 0.8 : 0.2), radius: glow ? 8 : 3)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.raveBackground.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 12) {
                RoomCardView(room: .preview)
                RoomCardView(room: Room(
                    id: "room_002",
                    name: "Chill Music 🎵",
                    hostID: "user_002",
                    hostName: "Jordan",
                    code: "XYZ789",
                    participants: (0..<8).map {
                        UserPreview(id: "u_\($0)", username: "User\($0)", avatarURL: nil, isOnline: true)
                    },
                    mediaItem: MediaItem(
                        id: "media_music",
                        title: "Lo-Fi Beats",
                        artist: "ChillHop",
                        thumbnailURL: nil,
                        streamURL: "",
                        duration: 3600,
                        mediaType: .music,
                        source: .url
                    ),
                    isActive: true,
                    maxParticipants: 20,
                    hostIsPremium: false,
                    createdAt: .now.addingTimeInterval(-7200)
                ))
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}
