//  HeroVideoBanner.swift
//  Plink — looping muted video promo banners (3 assets).

import SwiftUI
import AVFoundation
import UIKit

// MARK: - HeroVideoBanner

/// Looping muted video banner for hero carousel.
/// Falls back to catalog poster, then solid gradient — never blank.
struct HeroVideoBanner: View {
    let banner: HeroBannerKind
    var height: CGFloat = 260
    var showsOverlay: Bool = true
    var onPrimary: (() -> Void)? = nil
    var onSecondary: (() -> Void)? = nil

    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?
    @State private var failureObserver: NSObjectProtocol?
    @State private var videoFailed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 1: always-visible gradient base (never blank screen)
            LinearGradient(
                colors: [
                    banner.accentColor.opacity(0.55),
                    Color(hex: 0x0E1113),
                    Color(hex: 0x0A0D12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Layer 2: poster from Assets (imageset name == asset base, not *_poster)
            banner.posterImage
                .resizable()
                .aspectRatio(contentMode: .fill)
                .opacity(player == nil || videoFailed ? 1 : 0.15)

            // Layer 3: video
            if let player, !videoFailed {
                LoopingPlayerView(player: player)
                    .aspectRatio(contentMode: .fill)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            }

            // Gradient for text legibility
            LinearGradient(
                colors: [
                    .clear,
                    Color(hex: 0x0E1113).opacity(0.35),
                    Color(hex: 0x0E1113).opacity(0.92),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if showsOverlay {
                VStack(alignment: .leading, spacing: 8) {
                    Text(banner.title)
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 6)
                        .minimumScaleFactor(0.8)
                        .lineLimit(2)

                    Text(banner.subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(banner.accentColor)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Button {
                            onPrimary?()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Смотреть вместе")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0E1113))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onSecondary?()
                        } label: {
                            Text(banner.cta2)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(banner.title). \(banner.subtitle)")
    }

    private func setupPlayer() {
        guard player == nil else { return }
        guard let url = Self.resolveVideoURL(named: banner.assetName) else {
            videoFailed = true
            return
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .none
        p.isMuted = true
        p.automaticallyWaitsToMinimizeStalling = true
        if #available(iOS 16.0, *) {
            p.defaultRate = 1.0
        }

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }

        // If item fails, keep poster visible
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            videoFailed = true
        }

        player = p
        p.play()
    }

    private func teardownPlayer() {
        player?.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        loopObserver = nil
        failureObserver = nil
        player = nil
    }

    /// Bundle paths for folder-resource Banners + flat copy.
    static func resolveVideoURL(named name: String) -> URL? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Banners"),
            Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Resources/Banners"),
            Bundle.main.url(forResource: name, withExtension: "mp4"),
            Bundle.main.resourceURL?
                .appendingPathComponent("Banners", isDirectory: true)
                .appendingPathComponent("\(name).mp4"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

// MARK: - AVPlayerLayer host (no system chrome — unlike VideoPlayer)

private struct LoopingPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - HeroBannerKind

enum HeroBannerKind: CaseIterable, Identifiable {
    case watchTogether
    case aiCompanion
    case syncDevices

    var id: String { assetName }

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
        case .watchTogether: return "Создай комнату и зови друзей"
        case .aiCompanion:   return "Умный помощник для совместного просмотра"
        case .syncDevices:   return "Sync ±2s · iOS, Android, Mac, Windows"
        }
    }

    var cta2: String {
        switch self {
        case .watchTogether: return "Войти по коду"
        case .aiCompanion:   return "Plink+"
        case .syncDevices:   return "Как это работает"
        }
    }

    var accentColor: Color {
        switch self {
        case .watchTogether: return Color(hex: 0x2DE2E6)
        case .aiCompanion:   return Color(hex: 0x26D9A4)
        case .syncDevices:   return Color(hex: 0x0EB5C9)
        }
    }

    /// Asset catalog imageset is named without `_poster` suffix.
    var posterImage: Image {
        Image(assetName)
    }
}

// MARK: - HeroVideoCarousel

struct HeroVideoCarousel: View {
    var height: CGFloat = 260
    var onWatchTogether: (() -> Void)? = nil
    var onJoinByCode: (() -> Void)? = nil

    @State private var currentIndex = 0
    @State private var timer: Timer?

    private let banners = HeroBannerKind.allCases
    private let autoScrollInterval: TimeInterval = 5.5

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $currentIndex) {
                ForEach(Array(banners.enumerated()), id: \.offset) { index, banner in
                    HeroVideoBanner(
                        banner: banner,
                        height: height,
                        onPrimary: onWatchTogether,
                        onSecondary: {
                            if banner == .watchTogether { onJoinByCode?() }
                            else { onWatchTogether?() }
                        }
                    )
                    .padding(.horizontal, 13)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: height + 8)

            // Explicit page dots (in case page style hides them on dark bg)
            HStack(spacing: 6) {
                ForEach(0..<banners.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentIndex ? Color(hex: 0x2DE2E6) : Color.white.opacity(0.25))
                        .frame(width: i == currentIndex ? 8 : 6, height: i == currentIndex ? 8 : 6)
                }
            }
            .accessibilityHidden(true)
        }
        .onAppear { startAutoScroll() }
        .onDisappear { stopAutoScroll() }
    }

    private func startAutoScroll() {
        stopAutoScroll()
        timer = Timer.scheduledTimer(withTimeInterval: autoScrollInterval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.45)) {
                currentIndex = (currentIndex + 1) % banners.count
            }
        }
    }

    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}
