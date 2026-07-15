//  HeroVideoBanner.swift
//  Plink
//
//  Video banner component using 3 pre-loaded MP4 files.
//  1:1 with reference videos from Grok Imagine.
//

import SwiftUI
import AVKit
import Combine

// MARK: - HeroVideoBanner

/// Looping muted video banner for hero carousel.
/// Usage:
///   HeroVideoBanner(.watchTogether)
///   HeroVideoBanner(.aiCompanion)
///   HeroVideoBanner(.syncDevices)
struct HeroVideoBanner: View {
    let banner: HeroBannerKind
    var height: CGFloat = 480
    var showsOverlay: Bool = true

    @State private var player: AVPlayer?
    @State private var observer: NSObjectProtocol?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(height: height)
                    .clipped()
                    .onAppear { player.play() }
                    .onDisappear {
                        player.pause()
                        if let observer {
                            NotificationCenter.default.removeObserver(observer)
                        }
                    }
            } else {
                // Fallback: poster image
                banner.posterImage
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(height: height)
                    .clipped()
            }

            // Gradient overlay (top → bottom)
            LinearGradient(
                colors: [
                    .clear,
                    Color(hex: 0x0E1113).opacity(0.4),
                    Color(hex: 0x0E1113).opacity(0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)

            // Text overlay
            if showsOverlay {
                VStack(alignment: .leading, spacing: 8) {
                    Text(banner.title)
                        .font(.system(size: 34, weight: .800))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 8)

                    Text(banner.subtitle)
                        .font(.system(size: 14, weight: .600))
                        .foregroundStyle(banner.accentColor)
                        .shadow(color: .black.opacity(0.6), radius: 4)

                    HStack(spacing: 12) {
                        Button {
                            // TODO: open room creation
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Смотреть вместе")
                            }
                            .font(.system(size: 15, weight: .700))
                            .foregroundStyle(Color(hex: 0x0E1113))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color(hex: 0x2DE2E6).opacity(0.4), radius: 12)
                        }

                        Button {
                            // TODO: open Plink+ paywall
                        } label: {
                            Text(banner.cta2)
                                .font(.system(size: 15, weight: .600))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.06))
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(28)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { setupPlayer() }
    }

    private func setupPlayer() {
        guard player == nil,
              let url = Bundle.main.url(forResource: banner.assetName, withExtension: "mp4",
                                         subdirectory: "Banners") ?? {
                                             // Try Assets.xcassets fallback
                                             Bundle.main.url(forResource: banner.assetName, withExtension: "mp4")
                                         }()
        else { return }

        let p = AVPlayer(url: url)
        p.actionAtItemEnd = .none
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false

        // Loop forever
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }

        player = p
    }
}

// MARK: - HeroBannerKind

enum HeroBannerKind: CaseIterable {
    case watchTogether
    case aiCompanion
    case syncDevices

    var assetName: String {
        switch self {
        case .watchTogether: return "hero_banner_watch_together"
        case .aiCompanion:   return "hero_banner_ai_companion"
        case .syncDevices:   return "hero_banner_sync_devices"
        }
    }

    var title: String {
        switch self {
        case .watchTogether: return "Смотрим вместе"
        case .aiCompanion:   return "AI Companion"
        case .syncDevices:   return "Синхронный просмотр"
        }
    }

    var subtitle: String {
        switch self {
        case .watchTogether: return "Watch together. Anywhere. Together."
        case .aiCompanion:   return "Умный помощник для совместного просмотра"
        case .syncDevices:   return "Sync ±2s across iOS, Android, Mac, Windows"
        }
    }

    var cta2: String {
        switch self {
        case .watchTogether: return "Войти по коду"
        case .aiCompanion:   return "Plink+"
        case .syncDevices:   return "Скачать"
        }
    }

    var accentColor: Color {
        switch self {
        case .watchTogether: return Color(hex: 0x2DE2E6)
        case .aiCompanion:   return Color(hex: 0x26D9A4)
        case .syncDevices:   return Color(hex: 0x0EB5C9)
        }
    }

    var posterImage: Image {
        switch self {
        case .watchTogether: return Image("hero_banner_watch_together_poster")
        case .aiCompanion:   return Image("hero_banner_ai_companion_poster")
        case .syncDevices:   return Image("hero_banner_sync_devices_poster")
        }
    }
}

// MARK: - HeroVideoCarousel

/// Auto-scrolling carousel of all 3 video banners.
struct HeroVideoCarousel: View {
    @State private var currentIndex = 0
    @State private var timer: Timer?

    private let banners: [HeroBannerKind] = HeroBannerKind.allCases
    private let autoScrollInterval: TimeInterval = 6

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(banners.enumerated()), id: \.0) { index, banner in
                HeroVideoBanner(banner: banner)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 480)
        .onAppear { startAutoScroll() }
        .onDisappear { stopAutoScroll() }
    }

    private func startAutoScroll() {
        timer = Timer.scheduledTimer(withTimeInterval: autoScrollInterval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                currentIndex = (currentIndex + 1) % banners.count
            }
        }
    }

    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}
