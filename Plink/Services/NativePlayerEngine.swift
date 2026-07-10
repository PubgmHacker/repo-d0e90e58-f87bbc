import AVFoundation
import AVKit
import UIKit
import Combine

// MARK: - NativePlayerEngine (v90 — God-Mode AVPlayer)
//
// 🔧 v90 (Gemini): Singleton AVPlayer that lives OUTSIDE SwiftUI.
// AVPlayer + AVPlayerLayer in PlayerWindowContainer's UIWindow.
// SwiftUI communicates via @Published properties (event-driven, not hierarchical).
//
// Background handling:
//   - AVAudioSession .playback → audio continues in background
//   - AVPictureInPictureController → PiP starts automatically on background
//   - No forceResumePlayback, no reactivate(), no JS hacks needed!
//   - AVPlayer manages its own decoder — iOS can't sterilize it like WKWebView

@MainActor
final class NativePlayerEngine: ObservableObject {
    static let shared = NativePlayerEngine()

    // MARK: - Published State (for SwiftUI)

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var isLoading = false

    // MARK: - Private State

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var pipController: AVPictureInPictureController?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?

    /// v97: The User-Agent that ExtractionBridge's WKWebView uses to load
    /// m.youtube.com. We forward the SAME UA to the backend so YouTube's CDN
    /// sees a consistent client between extraction (iPhone WebView) and
    /// media-fetch (Railway proxy impersonating that same iPhone WebView).
    /// MUST stay in sync with ExtractionBridge.swift `wv.customUserAgent`.
    private static let webViewUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 " +
        "Mobile/15E148 Safari/604.1"

    private init() {
        configureAudioSession()
    }

    // MARK: - AVAudioSession

    /// Configure AVAudioSession for background playback + PiP.
    /// .playback: audio continues when app is backgrounded
    /// .moviePlayback: optimized for video playback
    /// .mixWithOthers: don't interrupt other audio apps
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            print("🔊 v90: AVAudioSession configured (.playback + .moviePlayback)")
        } catch {
            print("⚠️ v90: AVAudioSession error: \(error)")
        }
    }

    // MARK: - Load & Play

    /// v97: Transparent Proxy. iOS extracts googlevideo URL via ExtractionBridge,
    /// then asks the backend to fetch it on iOS's behalf. Backend strips the
    /// `ip` query param (which would otherwise 403 due to IP mismatch) and
    /// forwards iPhone UA + cookies + Referer. Backend IP is irrelevant.
    ///
    /// Priority:
    ///   1. b64url + cookies + UA   (v97 transparent proxy — PRIMARY, works)
    ///   2. videoId                 (v95 server-side extract — fallback, may 429)
    ///   3. direct URL              (non-YouTube, no relay needed)
    func loadAndPlay(streamURL: String, cookies: [HTTPCookie] = [], videoId: String? = nil) {
        guard let url = URL(string: streamURL) else {
            print("⚠️ v90: Invalid stream URL: \(streamURL.prefix(60))")
            return
        }

        isLoading = true

        let lowerURL = streamURL.lowercased()
        let finalURL: URL
        let backendBase = "https://plink-backend-production-ef31.up.railway.app"
        let token = KeychainHelper.read(for: "rave_auth_token") ?? ""

        // v97: Priority 1 — Transparent Proxy via b64url + cookies + UA.
        // iOS already extracted the googlevideo URL; backend just strips `ip`
        // and forwards with iPhone identity. This is the WORKING path.
        if lowerURL.contains("googlevideo.com") || lowerURL.contains("youtube.com") {
            // Base64-encode the googlevideo URL (backend will strip the `ip` param)
            let b64url = (streamURL.data(using: .utf8) ?? Data()).base64EncodedString()

            // Base64-encode cookies as a cookie header string
            let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            let b64cookies = (cookieString.data(using: .utf8) ?? Data()).base64EncodedString()

            // v97: Base64-encode the WebView User-Agent so the backend can
            // impersonate the same iPhone that performed the extraction.
            let uaData = Self.webViewUserAgent.data(using: .utf8) ?? Data()
            let b64ua = uaData.base64EncodedString()

            var relayComponents = URLComponents(string: "\(backendBase)/api/media/stream")!
            relayComponents.queryItems = [
                URLQueryItem(name: "b64url", value: b64url),
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "b64cookies", value: b64cookies),
                URLQueryItem(name: "b64ua", value: b64ua) // v97: WebView UA
            ]

            guard let relayURL = relayComponents.url else {
                print("⚠️ v97: Failed to create StreamRelay URL")
                return
            }

            finalURL = relayURL
            print("🎬 v97: StreamRelay transparent-proxy — b64url(\(b64url.count)) + cookies(\(cookies.count)) + UA(\(b64ua.count)) → backend")
        }
        // v97: Priority 2 — Fallback to videoId (server-side extraction).
        // Only used when streamURL is empty/not a googlevideo URL but we still
        // have a videoId. Backend tries Piped + yt-dlp (may 429/400 on Railway).
        else if let vid = videoId, !vid.isEmpty {
            var relayComponents = URLComponents(string: "\(backendBase)/api/media/stream")!
            relayComponents.queryItems = [
                URLQueryItem(name: "videoId", value: vid),
                URLQueryItem(name: "token", value: token)
            ]
            guard let relayURL = relayComponents.url else { return }
            finalURL = relayURL
            print("🎬 v97: StreamRelay fallback — server-side extraction for videoId=\(vid)")
        } else {
            // Non-YouTube URL — play directly (no relay needed)
            finalURL = url
            print("🎬 v94: Direct stream: \(streamURL.prefix(80))")
        }

        let asset = AVURLAsset(url: finalURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        let newItem = AVPlayerItem(asset: asset)

        // First time: create player + setup observers + PiP
        if player == nil {
            player = AVPlayer(playerItem: newItem)
            player?.automaticallyWaitsToMinimizeStalling = true
            player?.volume = 1.0
            player?.allowsExternalPlayback = true
            PlayerWindowContainer.shared.setPlayer(player!)
            setupPiP()
            addTimeObserver()
            observeStatus(newItem)
            observeDuration(newItem)
            print("🎬 v90: AVPlayer created (first time)")
        } else {
            // Subsequent loads: just replace item
            statusObservation?.invalidate()
            durationObservation?.invalidate()
            player?.replaceCurrentItem(with: newItem)
            observeStatus(newItem)
            observeDuration(newItem)
            print("🎬 v90: AVPlayer item replaced")
        }

        playerItem = newItem

        // Start playing
        player?.play()
        isPlaying = true
    }

    // MARK: - PiP

    /// Setup AVPictureInPictureController.
    /// Requires AVPlayerLayer to be visible in a view hierarchy (UIWindow).
    /// canStartPictureInPictureAutomaticallyFromInline = true → PiP starts
    /// automatically when app is backgrounded.
    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("📱 v90: PiP not supported on this device")
            return
        }

        pipController = AVPictureInPictureController(
            playerLayer: PlayerWindowContainer.shared.playerLayer
        )

        if let pip = pipController {
            if #available(iOS 14.2, *) {
                pip.canStartPictureInPictureAutomaticallyFromInline = true
            }
            pip.requiresLinearPlayback = false
            print("📱 v90: AVPictureInPictureController created — PiP ready")
        }
    }

    // MARK: - Playback Controls

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
    }

    func seekRelative(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    // MARK: - Attach / Detach (room lifecycle)

    /// Called when entering room. Shows the player window.
    func attach() {
        PlayerWindowContainer.shared.show()
        print("🎬 v90: NativePlayerEngine attached to room")
    }

    /// Called when leaving room. Hides the player window.
    /// Player is NOT destroyed — just hidden.
    func detach() {
        PlayerWindowContainer.shared.hide()
        pause()
        print("🎬 v90: NativePlayerEngine detached from room")
    }

    // MARK: - Time Observer

    private func addTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if time.seconds.isFinite {
                    self.currentTime = time.seconds
                }
            }
        }
    }

    // MARK: - KVO Observers

    private func observeStatus(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: .new) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    print("🎬 v90: AVPlayer ready to play — duration=\(self.duration)s")
                case .failed:
                    self.isLoading = false
                    print("⚠️ v90: AVPlayer failed: \(item.error?.localizedDescription ?? "unknown")")
                default:
                    break
                }
            }
        }
    }

    private func observeDuration(_ item: AVPlayerItem) {
        durationObservation = item.observe(\.duration, options: .new) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.duration.seconds.isFinite && item.duration.seconds > 0 {
                    self.duration = item.duration.seconds
                }
            }
        }
    }
}

// MARK: - YouTubeResourceLoaderDelegate (v91)
//
/// 🔧 v91 (Gemini): AVAssetResourceLoaderDelegate that injects User-Agent + Referer
/// headers into EVERY AVPlayer request (including Range requests).
///
/// How it works:
/// 1. NativePlayerEngine replaces "https://" with "youtube-proxy://" in the URL
/// 2. AVURLAsset with custom scheme → AVPlayer routes ALL requests through delegate
/// 3. Delegate receives each request, rewrites URL back to "https://"
/// 4. Delegate creates URLSession with custom headers (User-Agent + Referer)
/// 5. Delegate forwards request → receives data → feeds to AVPlayer
///
/// This is the ONLY reliable way to inject headers into AVPlayer requests.
/// AVURLAssetHTTPHeaderFieldsKey doesn't work for Range requests (AVPlayer
/// drops headers on subsequent Range requests → YouTube returns 403).

final class YouTubeResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {

    /// The original HTTPS URL (before custom scheme replacement)
    private let originalURL: URL

    /// Dedicated queue for resource loading (don't block main thread)
    let queue = DispatchQueue(label: "com.plink.youtube-resourceloader", qos: .userInitiated)

    /// Active URLSession for forwarding requests
    private let session: URLSession

    /// YouTube headers that must match the extraction request
    private let headers: [String: String]

    /// Cookies captured during extraction (v92)
    private let cookies: [HTTPCookie]

    init(originalURL: URL, cookies: [HTTPCookie] = []) {
        self.originalURL = originalURL
        self.cookies = cookies
        self.headers = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) " +
                          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 " +
                          "Mobile/15E148 Safari/604.1",
            "Referer": "https://www.youtube.com/",
            "Origin": "https://www.youtube.com"
        ]

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = headers
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        // 🔧 v92: Set cookies on the session config so they're sent with EVERY request
        config.httpCookieStorage?.setCookies(cookies, for: originalURL, mainDocumentURL: originalURL)
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)

        super.init()
        print("🔧 v92: YouTubeResourceLoaderDelegate created — \(cookies.count) cookies, host=\(originalURL.host ?? "?")")
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // Get the URL from the loading request
        guard let url = loadingRequest.request.url else {
            print("⚠️ v91: No URL in loading request")
            loadingRequest.finishLoading(with: NSError(domain: "Plink", code: -1, userInfo: nil))
            return false
        }

        // Convert custom scheme back to HTTPS
        let httpsURLString = url.absoluteString
            .replacingOccurrences(of: "youtube-proxy://", with: "https://")
        guard let httpsURL = URL(string: httpsURLString) else {
            print("⚠️ v91: Failed to convert URL to HTTPS: \(httpsURLString.prefix(60))")
            loadingRequest.finishLoading(with: NSError(domain: "Plink", code: -1, userInfo: nil))
            return false
        }

        // Create a new request with the HTTPS URL + headers
        var request = URLRequest(url: httpsURL)
        request.httpMethod = "GET"

        // Copy Range header if present (AVPlayer uses Range for seeking)
        if let range = loadingRequest.request.value(forHTTPHeaderField: "Range") {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        // Add YouTube headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Perform the request
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("⚠️ v91: ResourceLoader request failed: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ v91: Non-HTTP response")
                loadingRequest.finishLoading(with: NSError(domain: "Plink", code: -1, userInfo: nil))
                return
            }

            if httpResponse.statusCode != 200 && httpResponse.statusCode != 206 {
                print("⚠️ v91: HTTP \(httpResponse.statusCode) from YouTube")
                loadingRequest.finishLoading(with: NSError(
                    domain: "Plink", code: httpResponse.statusCode, userInfo: nil))
                return
            }

            // Fill in content information
            if let contentInfoRequest = loadingRequest.contentInformationRequest {
                contentInfoRequest.contentType = "video/mp4"
                contentInfoRequest.isByteRangeAccessSupported = true

                if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                   let length = Int64(contentLength) {
                    contentInfoRequest.contentLength = length
                } else if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                    // Parse "bytes 0-999/2000"
                    let parts = contentRange.split(separator: "/")
                    if parts.count >= 2, let total = Int64(parts[1]) {
                        contentInfoRequest.contentLength = total
                    }
                }
            }

            // Feed data to AVPlayer
            if let data = data {
                loadingRequest.dataRequest?.respond(with: data)
            }

            loadingRequest.finishLoading()
        }

        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // Request cancelled by AVPlayer (seeking, etc.)
    }
}
