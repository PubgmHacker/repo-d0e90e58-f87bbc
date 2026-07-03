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
                                ProgressView().tint(.raveAccent)
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
                    .background(Color.raveWarning)
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
                .foregroundColor(.raveTextPrimary)
                .lineLimit(1)

            // Хост + участники
            HStack(spacing: 4) {
                Text(room.hostName)
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.raveGreen)
                    Text("\(room.participantCount)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundColor(.raveGreen)
                }
            }
        }
        .frame(width: 160)
        .padding(.vertical, 4)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.raveCard
            Image(systemName: "photo.tv")
                .font(.system(size: 24))
                .foregroundColor(.raveSurface)
        }
        .frame(width: 160, height: 100)
    }

    /// Градиентный плейсхолдер с иконкой типа медиа
    private var thumbnailGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.raveSurface.opacity(0.6),
                    Color.raveCard,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: mediaIcon)
                .font(.system(size: 28))
                .foregroundColor(.raveTextTertiary)
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
                .foregroundColor(.raveTextPrimary)
            Spacer()
            Text("\(count)")
                .font(.caption.bold().monospacedDigit())
                .foregroundColor(.raveTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassCard(cornerRadius: 10, opacity: 0.05)
        }
    }
}
