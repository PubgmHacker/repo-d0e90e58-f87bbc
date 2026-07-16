// Plink/V4/V4HomeViewLive.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct V4HomeView: View {
    let theme: V4Theme
    let openRoom: () -> Void
    @State private var query = ""
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack { V4Avatar(letter: "П", theme: theme); Spacer(); V4RoundButton(symbol: "○") }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Heading(eyebrow: "СУББОТНИЙ ВЕЧЕР", title: "С кем смотрим?")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)
                HStack(spacing:9) {
                    Image(systemName:"magnifyingglass")
                    TextField("Видео, сервис или комната", text:$query).foregroundStyle(V4.ink)
                }.font(.system(size:13)).foregroundStyle(V4.muted).padding(.horizontal,13).frame(height:48)
                 .background(V4.searchBG).clipShape(RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(V4.line))
                 .padding(.horizontal,19).padding(.bottom,18)
                V4Hero(title:"Afterglow", meta:"5 друзей уже смотрят. Подключайся сразу.", button:"Смотреть вместе", height:300, theme:theme, action:openRoom)
                    .padding(.horizontal,13).padding(.bottom,28)
                HStack { Text("Сейчас вместе").font(.system(size:18.24,weight:.bold)); Spacer(); Text("Все").font(.system(size:12.16)).foregroundStyle(V4.accent) }
                    .padding(.horizontal,19).padding(.bottom,12)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                    V4MediaCard(title:"Кино без спойлеров",meta:"5 друзей · LIVE")
                    V4MediaCard(title:"Смешное на YouTube",meta:"3 друга · 12 мин")
                }.padding(.horizontal,19) }
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
}



// MARK: - AutoScrollCarousel — continuous slow auto-scrolling horizontal carousel
struct AutoScrollCarousel<T: Identifiable, Content: View>: View {
    let items: [T]
    let cardWidth: CGFloat
    @ViewBuilder let content: (T) -> Content

    @State private var offset: CGFloat = 0
    @State private var displayLink: Timer?
    @State private var userDragging = false
    @State private var pauseUntil: Date = .distantPast
    @State private var dragStartOffset: CGFloat = 0
    @State private var lastTick: Date = .distantPast

    private let spacing: CGFloat = 11
    private let sidePadding: CGFloat = 19
    private let speed: CGFloat = 22
    private let pauseAfterUserDrag: TimeInterval = 4.0

    private var contentWidth: CGFloat {
        CGFloat(items.count) * cardWidth + CGFloat(max(0, items.count - 1)) * spacing + sidePadding * 2
    }

    var body: some View {
        GeometryReader { geo in
            let w = contentWidth
            HStack(spacing: spacing) {
                Color.clear.frame(width: sidePadding, height: 1)
                ForEach(items) { item in content(item).id(item.id) }
                Color.clear.frame(width: sidePadding, height: 1)
            }
            .frame(width: w, alignment: .leading)
            .offset(x: offset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        userDragging = true
                        offset = dragStartOffset + value.translation.width
                        pauseUntil = Date().addingTimeInterval(pauseAfterUserDrag)
                    }
                    .onEnded { _ in
                        userDragging = false
                        if w > 0 { while offset <= -w { offset += w }; while offset > 0 { offset -= w } }
                        dragStartOffset = offset
                        pauseUntil = Date().addingTimeInterval(pauseAfterUserDrag)
                    }
            )
            .frame(width: geo.size.width, height: nil, alignment: .leading)
            .clipped()
        }
        .frame(height: 200)
        .onAppear { startAutoScroll() }
        .onDisappear { displayLink?.invalidate() }
    }

    private func startAutoScroll() {
        displayLink?.invalidate()
        lastTick = Date()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            guard !userDragging else { lastTick = Date(); return }
            guard Date() > pauseUntil else { lastTick = Date(); return }
            let now = Date()
            let dt = CGFloat(now.timeIntervalSince(lastTick))
            lastTick = now
            offset -= speed * dt
            let w = contentWidth
            if w > 0 { while offset <= -w { offset += w }; while offset > 0 { offset -= w } }
            dragStartOffset = offset
        }
    }
}

// MARK: - Live Screen Variants (P0: Real backend data)

struct V4HomeViewLive: View {
    let theme: V4Theme
    @Bindable var searchStore: V4SearchStore
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void
    var liveThemeIndex: Int = 0
    @State private var query = ""
    @State private var showUnifiedSearch = false
    @State private var showNotificationsSoon = false

    // Theme-aware colors — use Plink+ theme colors if active, else standard
    private var activeAccent: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.accentColor }
        return theme.accentColor
    }
    private var activeSecondary: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.secondaryAccent }
        return theme.secondaryAccent
    }
    private var activeBtnText: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.buttonTextColor }
        return theme.buttonTextColor
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack { V4Avatar(letter: "П", theme: theme, isPremium: PremiumStatusManager.shared.isPremium); Spacer(); NotificationInboxButton(unreadCount: 0, action: { showNotificationsSoon = true }) }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                .alert("Уведомления", isPresented: $showNotificationsSoon) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Inbox будет доступен в следующем обновлении")
                }
                V4Heading(eyebrow: "СУББОТНИЙ ВЕЧЕР", title: "С кем смотрим?")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)

                // Tappable search bar
                Button {
                    showUnifiedSearch = true
                } label: {
                    HStack(spacing:9) {
                        Image(systemName:"magnifyingglass")
                        Text("Видео, сервис или комната")
                            .foregroundStyle(V4.muted)
                        Spacer()
                    }
                    .font(.system(size:13))
                    .padding(.horizontal,13)
                    .frame(height:48)
                    .background(V4.searchBG)
                    .clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(RoundedRectangle(cornerRadius:16).stroke(V4.line))
                }
                .buttonStyle(.plain)
                .padding(.horizontal,19)
                .padding(.bottom,18)

                // Hero carousel — video promo banners first, then trending + promo cards
                // (P0-1: wire existing HeroVideoBanner MP4s; keep V4Hero + promoBanner as-is)
                TabView {
                    // MP4 promo banners (Resources/Banners/*.mp4)
                    HeroVideoBanner(banner: .watchTogether, height: 260)
                        .padding(.horizontal, 13)
                    HeroVideoBanner(banner: .aiCompanion, height: 260)
                        .padding(.horizontal, 13)
                    HeroVideoBanner(banner: .syncDevices, height: 260)
                        .padding(.horizontal, 13)

                    if !searchStore.trending.isEmpty {
                        ForEach(searchStore.trending.prefix(5)) { item in
                            V4Hero(
                                title: item.title,
                                meta: "YouTube · \(item.subtitle)",
                                button: "Смотреть вместе",
                                height: 260,
                                theme: theme,
                                action: {
                                    HapticManager.impact(.medium)
                                    Task { await createRoomFromTrending(item) }
                                },
                                liveThemeIndex: liveThemeIndex
                            )
                            .padding(.horizontal, 13)
                        }
                        // Promotional banners
                        promoBanner(
                            title: "Смотрите вместе",
                            subtitle: "Создай комнату и пригласи друзей смотреть кино синхронно",
                            icon: "person.2.fill",
                            action: { NotificationCenter.default.post(name: .plinkRoomCreated, object: nil) }
                        )
                        .padding(.horizontal, 13)
                        promoBanner(
                            title: "Plink+ премиум",
                            subtitle: "Живые темы, анимированные эмодзи и эксклюзивные функции",
                            icon: "crown.fill",
                            isPremium: true,
                            action: { /* TODO: open paywall */ }
                        )
                        .padding(.horizontal, 13)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 280)
                .padding(.bottom, 20)

                // "Популярное" — auto-scrolling carousel, bigger posters
                if !searchStore.trending.isEmpty {
                    HStack { Text("Популярное").font(.system(size:24,weight:.heavy)).foregroundStyle(V4.ink); Spacer() }
                        .padding(.horizontal,19).padding(.bottom,14)
                    AutoScrollCarousel(items: Array(searchStore.trending.prefix(10)), cardWidth: 250) { item in
                        trendingCard(item)
                    }
                    .padding(.bottom, 22)
                }

                // AUDIT: Quick Room — premium liquid glass button
                if !searchStore.trending.isEmpty {
                    Button {
                        HapticManager.impact(.medium)
                        if let first = searchStore.trending.first {
                            Task { await createRoomFromTrending(first) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Быстрая комната")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(activeBtnText)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .background(
                            ZStack {
                                LinearGradient(
                                    colors: [activeAccent.opacity(0.9), activeSecondary.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: activeAccent.opacity(0.3), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 18)
                }

                // Рекомендации — bigger cards, more prominent
                if searchStore.trending.count > 5 {
                    HStack { Text("Рекомендации").font(.system(size:22,weight:.heavy)).foregroundStyle(V4.ink); Spacer() }
                        .padding(.horizontal,19).padding(.bottom,12)
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:12) {
                        ForEach(searchStore.trending.suffix(8)) { item in
                            recommendationCard(item)
                        }
                    }.padding(.horizontal,19) }
                    .padding(.bottom, 8)
                }

                // "Смотрят сейчас" — poster-based cards: video thumbnail + viewer count + host
                HStack(spacing:8) {
                    Circle().fill(V4.danger).frame(width:8,height:8)
                        .shadow(color: V4.danger.opacity(0.6), radius: 4)
                    Text("СМОТРЯТ СЕЙЧАС")
                        .font(.system(size:13,weight:.heavy))
                        .tracking(1.4)
                    Spacer()
                }
                .foregroundStyle(V4.danger)
                .padding(.horizontal,19).padding(.top,32).padding(.bottom,14)

                VStack(spacing:10) {
                    if let rs = roomsStore, case .loaded = rs.state, !rs.rooms.isEmpty {
                        ForEach(rs.rooms.prefix(5)) { room in
                            watchingNowCard(room)
                        }
                    } else {
                        // Placeholder cards — show even when no active rooms
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing:12) {
                                RoundedRectangle(cornerRadius:8)
                                    .fill(V4.cardBG)
                                    .frame(width:108,height:64)
                                    .overlay(
                                        Image(systemName:"film")
                                            .font(.system(size:18))
                                            .foregroundStyle(V4.muted)
                                    )
                                VStack(alignment:.leading,spacing:4) {
                                    RoundedRectangle(cornerRadius:4).fill(V4.cardBG).frame(width:160,height:13)
                                    RoundedRectangle(cornerRadius:3).fill(V4.cardBG.opacity(0.6)).frame(width:90,height:10)
                                    RoundedRectangle(cornerRadius:3).fill(V4.cardBG.opacity(0.4)).frame(width:60,height:9)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .frame(minHeight:88)
                            .background(V4.cardBG.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius:14,style:.continuous))
                        }
                    }
                }
                .padding(.horizontal,19)
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
        .sheet(isPresented: $showUnifiedSearch) {
            UnifiedSearchView(searchStore: searchStore, roomsStore: roomsStore, openRoom: {
                showUnifiedSearch = false
                openRoom()
            })
            .preferredColorScheme(.dark)
        }
    }

    /// Create room from a specific trending video — used by hero + quick room.
    @ViewBuilder
    private func watchingNowCard(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.light)
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        } label: {
            HStack(spacing: 12) {
                // Poster thumbnail — 16:9 with rounded corners + LIVE badge
                ZStack(alignment: .bottomLeading) {
                    if let thumbStr = room.mediaItem?.thumbnailURL, let url = URL(string: thumbStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                ZStack {
                                    Rectangle().fill(theme.accentColor.opacity(0.15))
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(theme.accentColor.opacity(0.7))
                                }
                            }
                        }
                    } else {
                        ZStack {
                            Rectangle().fill(theme.accentColor.opacity(0.15))
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.accentColor.opacity(0.7))
                        }
                    }
                    if room.isActive {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(V4.danger, in: Capsule())
                            .padding(6)
                    }
                }
                .frame(width: 108, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(V4.line, lineWidth: 0.5)
                )

                // Room info column
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(2)
                    Text("Хост: \(room.hostName)")
                        .font(.system(size: 11))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(room.participantCount)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(theme.buttonTextColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.accentColor.opacity(0.85), in: Capsule())
                        Text("\(room.participantCount)/\(room.maxParticipants)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(V4.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.muted)
            }
            .padding(12)
            .frame(minHeight: 88)
            .background(V4.cardBG.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(room.isActive ? V4.danger.opacity(0.25) : V4.accent.opacity(0.08),
                            lineWidth: room.isActive ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Promotional banner for hero carousel
    private func promoBanner(title: String, subtitle: String, icon: String, isPremium: Bool = false, action: @escaping () -> Void) -> some View {
        let bannerAccent = isPremium ? Color(hex: "#A855F7") : activeAccent
        let bannerSecondary = isPremium ? Color(hex: "#EC4899") : activeSecondary
        return Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background gradient
                LinearGradient(
                    colors: [bannerAccent.opacity(0.3), Color.oklch(0.06, 0.01, 190)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Glow accent
                RadialGradient(colors: [bannerSecondary.opacity(0.4), .clear], center: UnitPoint(x: 0.75, y: 0.25), startRadius: 0, endRadius: 180)
                // Dark fade at bottom for text readability
                LinearGradient(colors: [.clear, Color.oklch(0.06, 0.01, 190, alpha: 0.9)], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    // Icon badge
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(bannerAccent.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        if isPremium {
                            Text("Plink+")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#A855F7"), in: Capsule())
                        }
                    }
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                    // CTA button
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                        Text(isPremium ? "Оформить" : "Создать")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(activeBtnText)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(
                        ZStack {
                            LinearGradient(colors: [bannerAccent.opacity(0.9), bannerSecondary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .center)
                        }
                    )
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: bannerAccent.opacity(0.3), radius: 10, y: 4)
                }
                .padding(.horizontal, 19)
                .padding(.bottom, 18)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
            .shadow(color: .black.opacity(0.40), radius: 27, y: 25)
        }
        .buttonStyle(.plain)
    }

    /// Trending card with thumbnail + title
    private func trendingCard(_ item: V4SearchResult) -> some View {
        let (_, _, _, accent) = theme.colors
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 14).fill(V4.cardBG)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(V4.cardBG)
                }
                RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.05))
                Text("YouTube")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
            .frame(width: 250, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .frame(width: 250, alignment: .leading)
        }
    }

    /// Smaller card for Рекомендации
    private func recommendationCard(_ item: V4SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(V4.cardBG)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(V4.cardBG)
                }
                RoundedRectangle(cornerRadius: 10).fill(theme.accentColor.opacity(0.03))
            }
            .frame(width: 170, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .frame(width: 170, alignment: .leading)
        }
    }

    /// Create room from a trending video — posts .plinkRoomCreated so
    /// PlinkApprovedV4Root picks it up and presents WatchRoom.
    private func createRoomFromTrending(_ item: V4SearchResult) async {
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        let videoId = item.id
        let mediaItem = MediaItem(
            id: "https://www.youtube.com/embed/\(videoId)",
            title: item.title, artist: nil,
            thumbnailURL: item.artworkURL?.absoluteString,
            streamURL: "https://www.youtube.com/embed/\(videoId)",
            duration: nil, mediaType: .video, source: .youtube, videoId: videoId
        )
        let request = CreateRoomRequest(
            name: item.title, maxParticipants: 4, mediaItem: mediaItem,
            privacy: .publicRoom, password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let api = APIClient.shared
            let room = try await RoomService(api: api).createRoom(request)
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
            }
        } catch {}
    }
}


