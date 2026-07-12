import SwiftUI

// MARK: - Friend Profile View
/// Профиль друга: аватарка, статистика (часы, друзья, комнаты),
/// история просмотров, кнопка отправить сообщение.
struct FriendProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiClient: APIClient
    let friend: Friend
    var onMessageTap: () -> Void

    // Реальная статистика с сервера
    @State private var roomsWatched = 0
    @State private var hoursWatched = 0
    @State private var friendsCount = 0
    @State private var isLoadingStats = true
    @State private var history: [FriendHistoryItem] = []

    var body: some View {
        ZStack {
            Cinema2026.background

            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    statsRow
                    actionButtons
                    watchHistorySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clear, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await loadStats() }
    }

    // MARK: - Load Stats (GET /api/users/:userId/stats) + Mock fallback

    private func loadStats() async {
        let api = apiClient
        guard api.authToken != nil else {
            applyMockStats()
            return
        }

        struct StatsDTO: Decodable {
            let friendsCount: Int
            let roomsJoined: Int
            let totalHoursWatched: Int
            let history: [HistoryDTO]?
        }
        struct HistoryDTO: Decodable {
            let mediaTitle: String
            let mediaPoster: String?
            let mediaType: String?
            let watchedAt: Date?
            let durationWatched: Int?
        }

        do {
            let stats: StatsDTO = try await api.request("users/\(friend.id)/stats")
            roomsWatched = stats.roomsJoined
            hoursWatched = stats.totalHoursWatched
            friendsCount = stats.friendsCount
            history = (stats.history ?? []).map { h in
                let typeIcon: String = {
                    switch h.mediaType {
                    case "movie": return "film"
                    case "series": return "tv"
                    case "music": return "music.note"
                    default: return "video"
                    }
                }()
                return FriendHistoryItem(
                    title: h.mediaTitle,
                    subtitle: "\(h.mediaType ?? "video")",
                    icon: typeIcon,
                    gradient: (.ravePrimary, .raveSecondary),
                    timeAgo: h.watchedAt?.formatted(.relative(presentation: .named)) ?? ""
                )
            }
        } catch {
            print("[FriendProfile] stats error: \(error.localizedDescription), using mock data")
            applyMockStats()
        }
        isLoadingStats = false
    }

    /// Mock-данные для тестирования, когда API недоступен
    private func applyMockStats() {
        roomsWatched = 24
        hoursWatched = 47
        friendsCount = 12
        history = [
            FriendHistoryItem(title: "Дюна: Часть вторая", subtitle: "movie", icon: "film", gradient: (.ravePrimary, .raveAccent), timeAgo: "2 часа назад"),
            FriendHistoryItem(title: "Lo-Fi Beats to Relax", subtitle: "music", icon: "music.note", gradient: (.raveCyan, .ravePrimary), timeAgo: "5 часов назад"),
            FriendHistoryItem(title: "The Witcher S3", subtitle: "series", icon: "tv", gradient: (.raveAccent, .raveWarning), timeAgo: "вчера"),
            FriendHistoryItem(title: "Cyberpunk 2077 стрим", subtitle: "livestream", icon: "dot.radiowaves", gradient: (.raveGreen, .raveCyan), timeAgo: "2 дня назад"),
            FriendHistoryItem(title: "Best Stand Up 2024", subtitle: "video", icon: "video", gradient: (.raveWarning, .raveAccent), timeAgo: "3 дня назад"),
        ]
        isLoadingStats = false
    }

    // MARK: - Stats

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            // Аватарка 110pt с glow
            ZStack {
                if let urlStr = friend.avatarURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            avatarFallback
                        }
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.raveGradient, lineWidth: 3))
                    .neonGlow(color: .ravePrimary, radius: 20, y: 8)
                } else {
                    avatarFallback
                        .frame(width: 110, height: 110)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.raveGradient, lineWidth: 3))
                        .neonGlow(color: .ravePrimary, radius: 20, y: 8)
                }
            }

            VStack(spacing: 4) {
                Text(friend.username)
                    .font(.title2.bold())
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(friend.isOnline ? Color.raveGreen : Color.raveTextTertiary)
                        .frame(width: 8, height: 8)
                    Text(friend.isOnline ? "В сети" : "Не в сети")
                        .font(.caption)
                        .foregroundColor(.raveTextSecondary)
                }
            }
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [.ravePrimary, .raveAccent],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Text(friend.initials)
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        Group {
            if isLoadingStats {
                ProgressView().tint(.ravePrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                HStack(spacing: 0) {
                    statBox(value: "\(roomsWatched)", label: "Комнат")
                    Divider().frame(height: 40).background(Color.white.opacity(0.06))
                    statBox(value: "\(hoursWatched)", label: "Часов")
                    Divider().frame(height: 40).background(Color.white.opacity(0.06))
                    statBox(value: "\(friendsCount)", label: "Друзей")
                }
                .padding(.vertical, 16)
            }
        }
        .glassCard(cornerRadius: 18, opacity: 0.04)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(.raveTextPrimary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.raveTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Отправить сообщение
            Button(action: onMessageTap) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.fill")
                    Text("Написать")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.raveGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .ravePrimary.opacity(0.3), radius: 10, y: 4)
            }

            // Добавить в комнату
            Button { } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("В комнату")
                        .font(.caption2.bold())
                }
                .foregroundColor(.raveTextPrimary)
                .frame(width: 90)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 14)
            }
        }
    }

    // MARK: - Watch History

    private var watchHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Что смотрел(а)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                Spacer()
                Text("\(history.count)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(.raveTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassCard(cornerRadius: 10, opacity: 0.05)
            }

            if history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundColor(.raveTextTertiary)
                    Text("Истории пока нет")
                        .font(.subheadline)
                        .foregroundColor(.raveTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .glassCard(cornerRadius: 14, opacity: 0.04)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(history) { item in
                        friendHistoryRow(item)
                    }
                }
            }
        }
    }

    private func friendHistoryRow(_ item: FriendHistoryItem) -> some View {
        HStack(spacing: 12) {
            // Превью
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(colors: [item.gradient.0, item.gradient.1],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary)
            }

            Spacer()

            Text(item.timeAgo)
                .font(.caption2)
                .foregroundColor(.raveTextTertiary)
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }
}

// MARK: - Mock Model

struct FriendHistoryItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let gradient: (Color, Color)
    let timeAgo: String
}
