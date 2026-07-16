import SwiftUI

/// Friend / public social profile: stats, badges, watch history, Watch Together.
struct FriendProfileView: View {
    let userId: String
    var usernameHint: String = ""
    var onWatchTogether: (() -> Void)? = nil

    @State private var profile: UserSocialProfile?
    @State private var error: String?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                statsGrid
                badgesSection
                historySection
                if let onWatchTogether {
                    Button {
                        onWatchTogether()
                    } label: {
                        Label("Смотреть вместе", systemImage: "play.rectangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Cinema2026.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Смотреть вместе")
                }
            }
            .padding(20)
        }
        .background(Cinema2026.background.ignoresSafeArea())
        .navigationTitle(profile?.displayTitle ?? usernameHint)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let url = PlinkAvatarURL.resolve(userId: userId, stored: profile?.avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            avatarLetter
                        }
                    }
                } else {
                    avatarLetter
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(Circle().stroke(Cinema2026.accent.opacity(0.4), lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.displayTitle ?? usernameHint)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                if let u = profile?.username {
                    Text("@\(u)")
                        .font(.system(size: 14))
                        .foregroundStyle(Cinema2026.secondary)
                }
                if profile?.isOnline == true {
                    Text("в сети")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Cinema2026.accent)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var avatarLetter: some View {
        ZStack {
            Circle().fill(Cinema2026.accent.opacity(0.25))
            Text(String((profile?.username ?? usernameHint).prefix(1)).uppercased())
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var statsGrid: some View {
        let p = profile
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard("Часы в Plink", p?.watchHoursText ?? "—")
            statCard("Фильмов", p.map { "\($0.filmsWatched)" } ?? "—")
            statCard("Друзей", p.map { "\($0.friendsCount)" } ?? "—")
            statCard("Комнат", p.map { "\($0.roomsCreated)" } ?? "—")
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Cinema2026.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    @ViewBuilder
    private var badgesSection: some View {
        if let badges = profile?.badges, !badges.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Достижения")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                FlowBadgeRow(codes: badges)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if let history = profile?.watchHistory, !history.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Недавно смотрел")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                ForEach(history.prefix(10)) { item in
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(Cinema2026.accent)
                        Text(item.title)
                            .font(.system(size: 14))
                            .foregroundStyle(Cinema2026.text)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isLoading {
            ProgressView().tint(Cinema2026.accent)
        } else if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await SocialProfileService.fetch(userId: userId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FlowBadgeRow: View {
    let codes: [String]

    var body: some View {
        FlexibleWrap(spacing: 8) {
            ForEach(codes, id: \.self) { code in
                let badge = ProfileBadge.from(code: code)
                HStack(spacing: 4) {
                    Image(systemName: badge?.symbol ?? "star")
                        .font(.system(size: 11, weight: .semibold))
                    Text(badge?.title ?? code)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Cinema2026.accent.opacity(0.35), in: Capsule())
                .accessibilityLabel(badge?.title ?? code)
            }
        }
    }
}

/// Minimal wrap layout for badges without external deps.
struct FlexibleWrap<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        // Simple horizontal scroll if many badges — keeps layout stable on all sizes
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content }
        }
    }
}
