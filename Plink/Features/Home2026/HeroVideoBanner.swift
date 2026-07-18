
// Plink/Features/Home2026/HeroVideoBanner.swift
// M11: Hero banners with real curated content

import SwiftUI

// MARK: - Hero Banner Item
struct HeroBannerItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let tag: String
    let gradientColors: [Color]
    let service: VideoService
    let actionLabel: String

    static let curated: [HeroBannerItem] = [
        HeroBannerItem(
            title: "Squid Game 2",
            subtitle: "Продолжение легенды — смотрите вместе",
            tag: "Netflix · Триллер",
            gradientColors: [Color(red: 0.86, green: 0.08, blue: 0.24), Color(red: 0.05, green: 0.05, blue: 0.1)],
            service: .netflix,
            actionLabel: "Смотреть вместе"
        ),
        HeroBannerItem(
            title: "Служанка злого духа",
            subtitle: "Мир аниме Миядзаки Хаяо на большом экране",
            tag: "Кинопоиск · 8.5",
            gradientColors: [Color(red: 0.1, green: 0.35, blue: 0.6), Color(red: 0.0, green: 0.05, blue: 0.15)],
            service: .kinopoisk,
            actionLabel: "Смотреть с друзьями"
        ),
        HeroBannerItem(
            title: "MrBeast: Последний остаётся",
            subtitle: "100+ млн просмотров — присоединяйся!",
            tag: "YouTube · Тренд",
            gradientColors: [Color(red: 0.8, green: 0.1, blue: 0.1), Color(red: 0.2, green: 0.0, blue: 0.0)],
            service: .youtube,
            actionLabel: "Смотреть вместе"
        ),
        HeroBannerItem(
            title: "Wednesday S2",
            subtitle: "Самый ожидаемый сезон этого года",
            tag: "Netflix · Комедия",
            gradientColors: [Color(red: 0.12, green: 0.12, blue: 0.35), Color(red: 0.02, green: 0.02, blue: 0.06)],
            service: .netflix,
            actionLabel: "Смотреть вместе"
        ),
        HeroBannerItem(
            title: "VK FEST 2024",
            subtitle: "Лучшие выступления фестиваля",
            tag: "VK Видео · Музыка",
            gradientColors: [Color(red: 0.22, green: 0.47, blue: 0.9), Color(red: 0.05, green: 0.1, blue: 0.2)],
            service: .vk,
            actionLabel: "Посмотреть"
        ),
    ]
}

// MARK: - Hero Video Carousel
struct HeroVideoCarousel: View {
    @State private var currentIndex: Int = 0
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private let items = HeroBannerItem.curated

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed paged banner
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HeroBannerCard(item: item)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 260)

            // Page indicator dots
            HStack(spacing: 6) {
                ForEach(0..<items.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentIndex ? Color.white : Color.white.opacity(0.35))
                        .frame(width: i == currentIndex ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: currentIndex)
                }
            }
            .padding(.bottom, 14)
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
    }
}

// MARK: - Single Hero Banner Card
struct HeroBannerCard: View {
    let item: HeroBannerItem
    @State private var showRoom = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: item.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Noise texture overlay for depth
            Rectangle()
                .fill(.black.opacity(0.15))

            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Service badge
                HStack(spacing: 6) {
                    ServiceLogoView(service: item.service, size: 16)
                    Text(item.tag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.12), in: Capsule())

                Text(item.title)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Button {
                    showRoom = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                        Text(item.actionLabel)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.2), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)

            // Decorative service logo (large, faded, right side)
            HStack {
                Spacer()
                ServiceLogoView(service: item.service, size: 90)
                    .opacity(0.12)
                    .padding(.trailing, 16)
                    .padding(.bottom, 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .sheet(isPresented: $showRoom) {
            RoomCreationView()
        }
    }
}
