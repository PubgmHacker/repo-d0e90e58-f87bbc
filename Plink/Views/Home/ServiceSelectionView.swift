import SwiftUI

// MARK: - Service Selection v5 — Premium List
///
/// 🔧 REDESIGNED: Was a 2×N grid ("сетка-винегрет"). Now a clean scrollable
/// list with real brand logos, premium row design, and section headers.
///
/// Structure:
///   1. Three category cards at top (Видеосервисы, Кинотеатры, Браузер)
///   2. Tapping a category opens a full-screen list of services
///   3. Each service row: real logo + name + subtitle + chevron
struct ServiceSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    /// 🔧 LEGACY: Called for browser/customURL (no content browsing needed).
    var onSelect: (VideoService) -> Void
    /// 🔧 NEW: Called when user picks content in a service browser.
    /// Passes: service, content URL, content title, thumbnailURL → parent opens RoomSetupView.
    /// 🔧 v33: added thumbnailURL — needed to show cover in "Смотрят сейчас" + history.
    var onContentSelected: (VideoService, String, String, String?) -> Void = { _, _, _, _ in }

    @State private var appeared = false
    @State private var selectedCategory: ServiceCategory?
    /// 🔧 NEW: When set, opens ServiceBrowserView for the selected service.
    @State private var browseService: VideoService?
    /// 🔧 v28 (July 2026): When set, opens YouTubeSearchView (native API
    /// search) instead of ServiceBrowserView (WKWebView). YouTube's anti-bot
    /// detects WKWebView and shows "Sign in to confirm you're not a bot" —
    /// there is NO way around this in WKWebView. The native search bypasses
    /// the bot check entirely because the search request goes through our
    /// backend (YouTube Data API v3) — the iPhone never touches youtube.com
    /// directly for search.
    @State private var showYouTubeSearch = false

    enum ServiceCategory: String, Identifiable {
        case video, cinema, browser
        var id: String { rawValue }
    }

    private let videoServices: [VideoService] = [.youtube, .vk, .rutube, .netflix, .disney]
    private let cinemaServices: [VideoService] = [.kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion]

    var body: some View {
        ZStack {
            Cinema2026.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                premiumNav

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Section header
                        PlinkSectionHeader(text: "Категория")
                            .padding(.top, 16)

                        // Three category cards
                        categoryCard(
                            title: "Видеосервисы",
                            subtitle: "YouTube · VK · Rutube · Netflix · Disney+",
                            icon: "play.rectangle.fill",
                            iconColor: Cinema2026.accent,
                            count: videoServices.count,
                            action: { selectedCategory = .video }
                        )

                        categoryCard(
                            title: "Кинотеатры",
                            subtitle: "Кинопоиск · Ivi · Okko · Wink · Start · Premier · Смотрим · KION",
                            icon: "film.stack",
                            iconColor: Cinema2026.accent,
                            count: cinemaServices.count,
                            action: { selectedCategory = .cinema }
                        )

                        categoryCard(
                            title: "Браузер / Своя ссылка",
                            subtitle: "Открой любой сайт или вставьте URL",
                            icon: "safari.fill",
                            iconColor: Cinema2026.accent,
                            count: nil,
                            action: { selectedCategory = .browser }
                        )

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
        .sheet(item: $selectedCategory) { category in
            switch category {
            case .video:
                ServiceListScreen(
                    title: "Видеосервисы",
                    services: videoServices,
                    onSelect: { service in
                        selectedCategory = nil
                        // 🔧 v28 (July 2026): YouTube uses native API search
                        // (YouTubeSearchView) instead of WKWebView browsing.
                        // YouTube's anti-bot blocks WKWebView with "Sign in
                        // to confirm you're not a bot" — there is no bypass.
                        // Native search goes through our backend (YouTube Data
                        // API v3) — the iPhone never touches youtube.com.
                        if service == .youtube {
                            showYouTubeSearch = true
                        } else {
                            browseService = service
                        }
                    }
                )
            case .cinema:
                ServiceListScreen(
                    title: "Кинотеатры",
                    services: cinemaServices,
                    onSelect: { service in
                        selectedCategory = nil
                        // Cinema services still use WebView — they require
                        // user login via their own auth, no API alternative.
                        browseService = service
                    }
                )
            case .browser:
                BrowserInputScreen { service in
                    selectedCategory = nil
                    onSelect(service)
                }
            }
        }
        // 🔧 v28: YouTube opens YouTubeSearchView (native API search).
        // Bypasses YouTube's WKWebView bot check entirely.
        .sheet(isPresented: $showYouTubeSearch) {
            YouTubeSearchView { contentURL, contentTitle, thumbnailURL in
                    showYouTubeSearch = false
                    onContentSelected(.youtube, contentURL, contentTitle, thumbnailURL)
                }
        }
        // 🔧 FIX: was .sheet — накапливал окна (sheet on sheet on sheet).
        // Now: .fullScreenCover — заменяет предыдущий экран, не накапливает.
        // User: 'вкладки предыдущие должны закрываться иначе создается 10+ окон'.
        .fullScreenCover(item: $browseService) { service in
            ServiceBrowserView(service: service) { contentURL, contentTitle in
                // 🔧 Pack v2: Сначала закрываем ServiceBrowserView,
                // потом с задержкой вызываем onContentSelected чтобы
                // RoomSetupView открылся поверх без конфликта sheet'ов.
                browseService = nil
                // 🔧 DEBUG: log what we're about to pass
                print("🔍 ServiceSelectionView: closing browser, will call onContentSelected with contentURL='\(contentURL)'")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onContentSelected(service, contentURL, contentTitle, nil)
                }
            }
        }
    }

    // MARK: - Premium Navigation

    private var premiumNav: some View {
        HStack {
            Button {
                HapticManager.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Cinema2026.text)
                    .frame(width: 40, height: 40)
                    .glassCard(cornerRadius: 20, opacity: 0.06)
            }
            .buttonStyle(PremiumButtonStyle(glowColor: .clear))

            Spacer()

            Text("Выбор сервиса")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Cinema2026.text)

            Spacer()

            Color.clear.frame(width: 40, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Category Card

    private func categoryCard(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        count: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            HStack(spacing: 14) {
                // Icon in colored rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(Cinema2026.text)
                        if let count {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundColor(Cinema2026.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Cinema2026.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Cinema2026.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }
}

// MARK: - Service List Screen (Premium scrollable list — replaces grid)
///
/// 🔧 REDESIGNED: Was a 2×N LazyVGrid ("сетка-винегрет"). Now a clean
/// vertical List with real brand logos, premium row design, and proper
/// section dividers.
struct ServiceListScreen: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let services: [VideoService]
    var onSelect: (VideoService) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Section header
                        PlinkSectionHeader(text: "Доступные сервисы")
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        // Grouped list in a single material card
                        VStack(spacing: 0) {
                            ForEach(Array(services.enumerated()), id: \.element) { index, service in
                                serviceRow(service)

                                // Thin divider between rows (not after last)
                                if index < services.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                        .padding(.leading, 72)
                                }
                            }
                        }
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 16)

                        // Footer info
                        Text("Выберите сервис, чтобы создать комнату для совместного просмотра")
                            .font(.system(size: 11))
                            .foregroundColor(Cinema2026.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 16)

                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Cinema2026.accent)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Service Row (premium list row with real logo + full brand name)

    @ViewBuilder
    private func serviceRow(_ service: VideoService) -> some View {
        Button {
            HapticManager.impact(.medium)
            onSelect(service)
        } label: {
            HStack(spacing: 14) {
                // 🔧 Real brand logo from Assets.xcassets (icon mode)
                ServiceLogoView(service: service, size: 40)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    // 🔧 Show full brand name (e.g. "VK Видео" not "VK")
                    Text(service.brandName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Cinema2026.text)
                    Text(service.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Cinema2026.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Cinema2026.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Browser Input Screen (поле ввода URL) — unchanged
struct BrowserInputScreen: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (VideoService) -> Void
    @State private var url = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Cinema2026.accent.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "safari.fill")
                            .font(.system(size: 36))
                            .foregroundColor(Cinema2026.accent)
                    }

                    VStack(spacing: 8) {
                        Text("Браузер / Своя ссылка")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Cinema2026.text)
                        Text("Вставьте ссылку на видео или сайт")
                            .font(.system(size: 15))
                            .foregroundColor(Cinema2026.secondary)
                    }

                    TextField("https://...", text: $url)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                        .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        Button {
                            HapticManager.impact(.medium)
                            onSelect(.browser)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                Text("Открыть браузер")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Cinema2026.accent.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.accent.opacity(0.4), lineWidth: 0.5))
                        }

                        Button {
                            HapticManager.impact(.medium)
                            onSelect(.customURL)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                Text("По ссылке")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Cinema2026.accentAction)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
                .dismissKeyboardOnTap()
            }
            .navigationTitle("Браузер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Cinema2026.accent)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ServiceSelectionView(onSelect: { _ in })
}
