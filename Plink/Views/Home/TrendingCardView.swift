import SwiftUI

// MARK: - Trending Card View (Premium Silver)
/// Компактная карточка для горизонтальных секций (Тренды, Сейчас смотрят).
struct TrendingCardView: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Миниатюра
            ZStack(alignment: .topTrailing) {
                if let mediaItem = room.mediaItem, let thumbURL = mediaItem.thumbnailURL, !thumbURL.isEmpty {
                    AsyncImage(url: URL(string: thumbURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 160, height: 100)
                                .clipped()
                        case .failure:
                            thumbnailPlaceholder
                        default:
                            ZStack {
                                thumbnailPlaceholder
                                ProgressView().tint(Cinema2026.accent)
                            }
                        }
                    }
                } else {
                    thumbnailGradient
                }

                // LIVE бейдж
                if room.isActive {
                    LiveBadge()
                        .padding(6)
                }

                // Premium бейдж
                if room.hostIsPremium {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                        Text("PRO")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundColor(Color(hex: 0x14161C))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Cinema2026.accent)
                    .clipShape(Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: 160, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            // Название
            Text(room.name)
                .font(.subheadline.bold())
                .foregroundColor(Cinema2026.text)
                .lineLimit(1)

            // Хост + участники
            HStack(spacing: 4) {
                Text(room.hostName)
                    .font(.caption2)
                    .foregroundColor(Cinema2026.secondary)
                    .lineLimit(1)

                Spacer()

                // 🔧 Participant badge (glass)
                ParticipantBadge(count: room.participantCount)
            }
        }
        .frame(width: 160)
        .padding(.vertical, 4)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Cinema2026.surface
            Image(systemName: "photo.tv")
                .font(.system(size: 24))
                .foregroundColor(Cinema2026.raised)
        }
        .frame(width: 160, height: 100)
    }

    /// Градиентный плейсхолдер с иконкой типа медиа
    private var thumbnailGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Cinema2026.raised.opacity(0.6),
                    Cinema2026.surface,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: mediaIcon)
                .font(.system(size: 28))
                .foregroundColor(Cinema2026.tertiary)
        }
        .frame(width: 160, height: 100)
    }

    private var mediaIcon: String {
        switch room.mediaItem?.mediaType {
        case .movie: return "film"
        case .series: return "tv"
        case .music: return "music.note"
        case .livestream: return "dot.radiowaves.left.and.right"
        default: return "play.rectangle"
        }
    }
}

// MARK: - Horizontal Section Header
struct HorizontalSectionHeader: View {
    let icon: String
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.title3)
            Text(title)
                .font(.headline)
                .foregroundColor(Cinema2026.text)
            Spacer()
            Text("\(count)")
                .font(.caption.bold().monospacedDigit())
                .foregroundColor(Cinema2026.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassCard(cornerRadius: 10, opacity: 0.05)
        }
    }
}
