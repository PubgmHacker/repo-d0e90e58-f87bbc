// Plink/AppShell/HomeComponents.swift — GPT-5.6 V4
// Components used by PlinkPhoneTabShell.homeView

import SwiftUI

// MARK: - Netflix Hero Banner
struct NetflixHeroBanner: View {
    let video: YouTubeVideoSummary
    let onTap: (SelectedContentDraft) -> Void

    private var draft: SelectedContentDraft {
        SelectedContentDraft(
            id: video.videoId,
            service: .youtube,
            contentURL: "https://www.youtube.com/watch?v=\(video.videoId)",
            title: video.title,
            thumbnailURL: video.thumbnailURLString
        )
    }

    var body: some View {
        Button { onTap(draft) } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: video.thumbnailURLString ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(height: 280)
                .clipped()

                LinearGradient(stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: Cinema2026.background.opacity(0.6), location: 0.7),
                    .init(color: Cinema2026.background, location: 1.0)
                ], startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 6) {
                    Text("● В ЭФИРЕ")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Cinema2026.danger)
                    Text(video.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                    Text(video.channelTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Cinema2026.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                        Text("Смотреть вместе").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Cinema2026.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Cinema2026.text, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .frame(height: 280)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plink Popular
struct PlinkPopularItem: Decodable, Identifiable, Sendable, Hashable {
    let contentURL: String
    let title: String
    let thumbnailURL: String?
    let uniqueViewers: Int
    let uniqueRooms: Int
    let recentStarts: Int
    let directCreateRoomDraft: Bool
    var id: String { contentURL }
}

struct PlinkPopularResponse: Decodable, Sendable {
    let results: [PlinkPopularItem]
}

struct PlinkPopularRail: View {
    let title: String
    let items: [PlinkPopularItem]
    let onSelect: (PlinkPopularItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Cinema2026.amber)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topLeading) {
                                    AsyncImage(url: URL(string: item.thumbnailURL ?? "")) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle().fill(Cinema2026.surface)
                                    }
                                    .frame(width: 186, height: 105)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    HStack(spacing: 3) {
                                        Image(systemName: "person.2.fill").font(.system(size: 8, weight: .bold))
                                        Text("\(item.uniqueViewers)").font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(.black.opacity(0.75), in: Capsule())
                                    .foregroundStyle(.white).padding(6)
                                }
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Cinema2026.text)
                                    .lineLimit(1)
                                    .frame(width: 186, alignment: .leading)
                                Text("\(item.uniqueRooms) комнат")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Cinema2026.secondary)
                                    .frame(width: 186, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!item.directCreateRoomDraft)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
        }
    }
}
