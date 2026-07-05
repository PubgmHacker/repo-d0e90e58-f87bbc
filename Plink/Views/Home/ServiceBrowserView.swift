import SwiftUI
import WebKit

// MARK: - ServiceBrowserView
/// 🔧 REDESIGNED: Full-screen WebView with smart video page detection.
///
/// When the user navigates to a video page in the service's catalog:
///   • For YouTube/VK/Rutube: detects the video page URL pattern automatically
///     and offers to "Создать комнату" with the embeddable URL
///   • For cinema services (Kinopoisk, Ivi, Okko, etc.): the page URL itself
///     becomes the content URL — the WebView acts as the player in the room
///
/// Auth requirements:
///   • YouTube, VK Video, Rutube: NO auth required for public content
///   • Kinopoisk, Ivi, Okko, Wink, Start, Premier, KION: subscription required
///     (user logs in via the WebView; cookies persist between sessions)
///   • Смотрим: free (state TV, no subscription)
///
/// The "Создать комнату" button is always available at the bottom, but when
/// a video page is detected, a prominent banner appears prompting the user
/// to create a room with the detected content.
struct ServiceBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let service: VideoService
    /// 🔧 Passes content URL + title to parent for RoomSetupView
    var onCreateRoom: (String, String) -> Void

    @State private var currentURL: URL?
    @State private var pageTitle: String = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var showCreateConfirm = false
    /// 🔧 NEW: When a video page is detected, this is set to the detected video info
    @State private var detectedVideo: DetectedVideo?
    /// 🔧 NEW: Whether this service requires auth for content
    @State private var showAuthBanner: Bool

    init(service: VideoService, onCreateRoom: @escaping (String, String) -> Void) {
        self.service = service
        self.onCreateRoom = onCreateRoom
        self._showAuthBanner = State(initialValue: service.requiresAuth)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.raveBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 🔧 Auth banner (shown for subscription services)
                    if showAuthBanner {
                        authBanner
                    }

                    // WebView
                    ServiceWebView(
                        initialURL: URL(string: service.browseURL)!,
                        currentURL: $currentURL,
                        pageTitle: $pageTitle,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        onVideoDetected: { video in
                            detectedVideo = video
                        }
                    )

                    // 🔧 Pack v3: bottomBar убран — авто-переход через onChange
                    // Кнопка "Создать комнату" больше не нужна — видео автоматически
                    // открывает RoomSetupView.
                }
            }
            .navigationTitle(service.brandName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.bioCyan)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            // 🔧 Pack v3: АВТО-переход — мгновенно, без задержки
            .onChange(of: detectedVideo) { _, newVideo in
                guard let video = newVideo else { return }
                HapticManager.impact(.medium)
                // 🔧 DEBUG: log what we're passing to onCreateRoom
                print("🔍 ServiceBrowserView: detected video, embedURL='\(video.embedURL)', title='\(video.title ?? "nil")', pageTitle='\(pageTitle)'")
                onCreateRoom(video.embedURL, video.title ?? pageTitle)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Auth Banner

    private var authBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundColor(.raveWarning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Требуется подписка \(service.brandName)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.raveTextPrimary)
                Text("Войдите в свой аккаунт для доступа к контенту. YouTube, VK Видео и Rutube не требуют входа.")
                    .font(.system(size: 10))
                    .foregroundColor(.raveTextSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation { showAuthBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.raveTextTertiary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.raveWarning.opacity(0.08))
        .overlay(Rectangle().fill(Color.raveWarning.opacity(0.2)).frame(height: 0.5))
    }

    // MARK: - Video Detected Banner

    private func videoDetectedBanner(video: DetectedVideo) -> some View {
        HStack(spacing: 12) {
            // Service logo
            ServiceLogoView(service: service, size: 32)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Видео найдено!")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.bioEmerald)
                Text(video.title ?? pageTitle)
                    .font(.system(size: 12))
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                HapticManager.impact(.medium)
                showCreateConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Комната")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.raveGradient)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(LinearGradient(colors: [Color.bioEmerald.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .offset(y: -22)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pageTitle.isEmpty ? "Выберите контент" : pageTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)
                if let url = currentURL {
                    Text(url.host ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.raveTextTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                HapticManager.impact(.medium)
                showCreateConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Создать комнату")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.raveGradient)
                .clipShape(Capsule())
                .shadow(color: .ravePrimary.opacity(0.4), radius: 8, y: 3)
            }
            .disabled(currentURL == nil)
            .opacity(currentURL == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Detected Video Model

struct DetectedVideo: Equatable {
    let title: String?
    let embedURL: String       // URL that can be used in our player
    let originalURL: String    // original page URL
    let service: VideoService
}

// MARK: - VideoService + Auth Requirements

extension VideoService {
    /// 🔧 Returns true if this service requires authentication/subscription for content.
    /// YouTube, VK Video, and Rutube have free public content.
    /// Cinema services require subscription.
    var requiresAuth: Bool {
        switch self {
        case .youtube, .vk, .rutube, .smotrim, .browser, .customURL:
            return false  // free / public content
        case .netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .kion:
            return true   // subscription required
        }
    }

    /// 🔧 Detects if a URL is a video page for this service, and returns the
    /// embeddable video URL if so. Returns nil if the URL is not a video page.
    static func detectVideoURL(_ url: URL, for service: VideoService, title: String?) -> DetectedVideo? {
        let urlString = url.absoluteString
        let host = url.host ?? ""

        switch service {
        case .youtube:
            // youtube.com/watch?v=VIDEO_ID or youtu.be/VIDEO_ID
            if host.contains("youtube.com") {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
                    return DetectedVideo(
                        title: title,
                        embedURL: "https://www.youtube.com/embed/\(videoId)",
                        originalURL: urlString,
                        service: .youtube
                    )
                }
            }
            if host.contains("youtu.be") {
                let videoId = url.lastPathComponent
                if !videoId.isEmpty {
                    return DetectedVideo(
                        title: title,
                        embedURL: "https://www.youtube.com/embed/\(videoId)",
                        originalURL: urlString,
                        service: .youtube
                    )
                }
            }

        case .vk:
            // vk.com/video-OWNER_ID_VIDEO_ID or vk.com/video/OWNER_ID_VIDEO_ID
            if host.contains("vk.com") || host.contains("vk.ru") {
                let path = url.path
                if path.contains("/video") {
                    // For VK, we use the original URL — VK's player works in WebView
                    return DetectedVideo(
                        title: title,
                        embedURL: urlString,
                        originalURL: urlString,
                        service: .vk
                    )
                }
            }

        case .rutube:
            // rutube.ru/video/VIDEO_ID/
            if host.contains("rutube.ru") || host.contains("rutube.video") {
                let path = url.path
                if path.contains("/video/") {
                    // Extract video ID from path
                    let segments = path.split(separator: "/")
                    if segments.count >= 2, segments[0] == "video" {
                        let videoId = String(segments[1])
                        return DetectedVideo(
                            title: title,
                            embedURL: "https://rutube.ru/play/embed/\(videoId)",
                            originalURL: urlString,
                            service: .rutube
                        )
                    }
                }
            }

        case .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion, .netflix, .disney:
            // For cinema services, detect video/content pages by URL patterns
            // These services use their own players with DRM — we can't extract streams
            // Instead, the page URL itself becomes the content URL
            // The WebView will be the player in the room
            let path = url.path.lowercased()
            // Common patterns: /film/, /series/, /video/, /watch/, /play/
            let videoPatterns = ["/film/", "/series/", "/video/", "/watch/", "/play/", "/movies/", "/show/"]
            if videoPatterns.contains(where: { path.contains($0) }) {
                return DetectedVideo(
                    title: title,
                    embedURL: urlString,  // use original URL — WebView is the player
                    originalURL: urlString,
                    service: service
                )
            }

        case .browser, .customURL:
            // No auto-detection for browser/customURL
            break
        }

        return nil
    }
}

// MARK: - ServiceWebView (WKWebView wrapper with video detection)

struct ServiceWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURL: URL?
    @Binding var pageTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    /// 🔧 NEW: Called when a video page is detected
    var onVideoDetected: ((DetectedVideo) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // 🔧 v25 (July 2026): ISOLATED, NON-PERSISTENT data store for the
        // search browser.
        //
        // The previous call to WKWebsiteDataStore.default() returned the
        // app-wide SHARED store. That store is shared with VideoContainerView
        // (the room player), which uses a custom plink-media:// scheme handler
        // and a modified User-Agent. Once that store accumulated cookies +
        // cache entries from the room player, YouTube's anti-bot heuristics
        // flagged it (the WebContent process saw inconsistent fingerprints
        // across the two contexts) and started returning the consent /
        // language-selection interstitial on the search screen as well.
        //
        // Switching to .nonPersistent() gives the search browser a FRESH,
        // isolated store on every launch — YouTube sees a clean Safari-like
        // session and skips the interstitial. Cookies set during search do
        // NOT persist across app launches, which is fine for a video search
        // screen (the user is browsing, not logging in here).
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        // 🔧 Pack v3: Register message handler for SPA URL changes.
        // NOTE: this is a coordinator-only message handler, NOT a script
        // injection — YouTube's anti-bot JS cannot see it from the page
        // context (it only sees whatever we add via addUserScript). Keeping
        // this handler is safe; it does not change the page's fingerprint.
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "plinkURLChange")

        // 🔧 v25: NO injected scripts for YouTube.
        //
        // v9.3 injected an `overflow-x:hidden` style. Even though the script
        // itself is benign, the act of running any WKUserScript at
        // .atDocumentEnd over the YouTube page gives YouTube's anti-bot JS
        // a measurable signal (it can detect document_end script injection
        // timing). Removing the script makes our WKWebView look more like
        // stock Safari.
        //
        // The overflow-x:hidden was only a "safety net" for minor horizontal
        // scroll glitches on m.youtube.com — m.youtube.com's own CSS handles
        // this fine in 2026, so the safety net is no longer worth the
        // detection cost.
        if initialURL.host?.contains("youtube.com") != true &&
           initialURL.host?.contains("youtu.be") != true {
            // For non-YouTube services (Rutube, VK, etc.) we still allow
            // future script injection here — those services don't run the
            // same anti-bot heuristics.
        }

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // 🔧 v25 (July 2026): REMOVED customUserAgent for YouTube.
        //
        // Previously this set an iPad Safari UA, hoping YouTube would serve
        // the modern mobile m.youtube.com layout. That worked initially, but
        // once the shared websiteDataStore got "marked" by earlier 153
        // failures (sandbox errors, DownloadFailed) YouTube's anti-bot
        // started treating the iPad UA from a WKWebView process as
        // inconsistent — iPad UA but no iPad Safari cookies, no Safari
        // fingerprint, no real iPad device attestation. Result: language
        // selection screen + "Sign in to confirm you're not a bot".
        //
        // Fix: leave customUserAgent UNSET. iOS will send the system's
        // native WKWebView UA, which is itself an iPhone Safari UA variant
        // (e.g. "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)
        // AppleWebKit/605.1.15 (KHTML, like Gecko) ... Version/17.5
        // Mobile/15E148 Safari/604.1"). This is the closest WKWebView can
        // get to real Safari — YouTube accepts it for m.youtube.com without
        // throwing the consent interstitial.

        webView.load(URLRequest(url: initialURL))

        webView.isOpaque = false
        webView.backgroundColor = UIColor(Color.raveBackground)
        webView.scrollView.backgroundColor = UIColor(Color.raveBackground)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        DispatchQueue.main.async {
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let parent: ServiceWebView
        private var lastDetectedURL: String?

        init(parent: ServiceWebView) {
            self.parent = parent
        }

        // 🔧 Pack v3: Handle SPA URL changes from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "plinkURLChange",
               let body = message.body as? [String: Any],
               let urlString = body["url"] as? String,
               let url = URL(string: urlString) {

                let title = body["title"] as? String
                let service = Self.serviceFromURL(url)
                if let service, let detected = VideoService.detectVideoURL(url, for: service, title: title) {
                    DispatchQueue.main.async {
                        self.parent.currentURL = url
                        self.parent.pageTitle = title ?? ""
                        self.parent.onVideoDetected?(detected)
                    }
                }
            }
        }

        // 🔧 Pack v3: Перехватываем КАЖДУЮ навигацию (включая SPA YouTube).
        // Раньше: только didFinish → YouTube SPA не триггерит → видео играло без создания комнаты.
        // Теперь: decidePolicyFor ловит URLchange → детектим видео → авто-переход.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Сначала проверяем URL на видео
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString
                // Избегаем повторного срабатывания на тот же URL
                if urlString != lastDetectedURL {
                    lastDetectedURL = urlString
                    let service = Self.serviceFromURL(url)
                    if let service, let detected = VideoService.detectVideoURL(url, for: service, title: nil) {
                        // 🔧 FIX: CANCEL navigation — don't load the YouTube watch page.
                        // Was: .allow → YouTube watch page loaded → video auto-played for
                        // a second before room creation took over.
                        // Now: .cancel → YouTube watch page never loads, no video playback.
                        // We just extract the video ID from the URL and create the room.
                        DispatchQueue.main.async {
                            self.parent.currentURL = url
                            self.parent.pageTitle = webView.title ?? ""
                            self.parent.onVideoDetected?(detected)
                        }
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.currentURL = webView.url
                self.parent.pageTitle = webView.title ?? ""
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }

            // 🔧 Detect video page on full load too
            if let url = webView.url {
                let title = webView.title
                let service = Self.serviceFromURL(url)
                if let service, let detected = VideoService.detectVideoURL(url, for: service, title: title) {
                    DispatchQueue.main.async {
                        self.parent.onVideoDetected?(detected)
                    }
                }
            }

            // 🔧 v25 (July 2026): SKIP all JS/CSS injection on YouTube.
            //
            // YouTube's anti-bot heuristics detect `evaluateJavaScript` calls
            // by timing and side-effects (window._plinkURLObserver global,
            // injected <style> nodes). On m.youtube.com, the History API
            // URL observer is also unnecessary — `decidePolicyFor` already
            // catches every navigation (including SPA route changes via
            // pushState) BEFORE the page loads. The observer was a legacy
            // fallback from when YouTube used `pushState` without triggering
            // a navigation delegate callback; in 2026 m.youtube.com triggers
            // a navigation delegate on every route change, so the observer
            // is dead weight that just costs us a fingerprint.
            //
            // For non-YouTube services (Rutube, VK, cinema) we still inject
            // the SPA observer + dark CSS — those services don't run anti-bot
            // heuristics, and some of them (Rutube) genuinely need the
            // observer to detect video page transitions.
            let isYouTubePage = webView.url?.host?.contains("youtube.com") == true ||
                                webView.url?.host?.contains("youtu.be") == true
            guard !isYouTubePage else { return }

            // 🔧 Pack v3: Inject JS to detect SPA URL changes (Rutube React app
            // and other services that use History API without full reload).
            let js = """
            (function() {
                if (window._plinkURLObserver) return;
                window._plinkURLObserver = true;
                let lastURL = window.location.href;
                setInterval(function() {
                    if (window.location.href !== lastURL) {
                        lastURL = window.location.href;
                        try {
                            window.webkit.messageHandlers.plinkURLChange.postMessage({
                                url: lastURL,
                                title: document.title
                            });
                        } catch(e) {}
                    }
                }, 500);
            })();
            """

            // Inject dark CSS
            let darkCSS = """
            :root { color-scheme: dark; }
            body { background-color: #0A0D14 !important; }
            """
            let cssJS = """
            var style = document.createElement('style');
            style.textContent = '\(darkCSS)';
            document.head.appendChild(style);
            """

            webView.evaluateJavaScript(js)
            webView.evaluateJavaScript(cssJS)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.pageTitle = "Ошибка загрузки"
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // 🔧 FIX: Rutube opens video in new window. Check for video URL before loading.
            if let url = navigationAction.request.url {
                let service = Self.serviceFromURL(url)
                if let service, let detected = VideoService.detectVideoURL(url, for: service, title: nil) {
                    DispatchQueue.main.async {
                        self.parent.currentURL = url
                        self.parent.pageTitle = webView.title ?? ""
                        self.parent.onVideoDetected?(detected)
                    }
                    return nil  // Don't open new window — go straight to room creation
                }
                // Not a video — load in current webView
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // 🔧 Helper: determine VideoService from URL host
        private static func serviceFromURL(_ url: URL) -> VideoService? {
            let host = (url.host ?? "").lowercased()
            if host.contains("youtube") || host.contains("youtu.be") { return .youtube }
            if host.contains("vk.com") || host.contains("vk.ru") { return .vk }
            if host.contains("rutube") { return .rutube }
            if host.contains("netflix") { return .netflix }
            if host.contains("disney") { return .disney }
            if host.contains("kinopoisk") { return .kinopoisk }
            if host.contains("ivi.ru") || host.contains("ivi.tv") { return .ivi }
            if host.contains("okko") { return .okko }
            if host.contains("wink") { return .wink }
            if host.contains("start.ru") { return .start }
            if host.contains("premier") { return .premier }
            if host.contains("smotrim") { return .smotrim }
            if host.contains("kion") { return .kion }
            return nil
        }
    }
}
