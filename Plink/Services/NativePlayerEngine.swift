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

    /// Custom scheme resource loader for injecting headers into AVPlayer requests.
    /// YouTube requires User-Agent + Referer to match the extraction request.
    private var resourceLoaderDelegate: YouTubeResourceLoaderDelegate?

    /// Load a stream URL and start playing.
    /// For googlevideo.com URLs, uses AVAssetResourceLoaderDelegate to inject
    /// User-Agent + Referer headers into EVERY request (including Range requests).
    /// AVURLAssetHTTPHeaderFieldsKey doesn't work reliably for Range requests.
    /// 🔧 v92: Also passes cookies from ExtractionBridge to avoid 403.
    func loadAndPlay(streamURL: String, cookies: [HTTPCookie] = []) {
        guard let url = URL(string: streamURL) else {
            print("⚠️ v90: Invalid stream URL: \(streamURL.prefix(60))")
            return
        }

        isLoading = true
        print("🎬 v91: Loading stream: \(streamURL.prefix(80))")

        let lowerURL = streamURL.lowercased()
        let asset: AVAsset

        if lowerURL.contains("googlevideo.com") {
            // 🔧 v91: Use AVAssetResourceLoaderDelegate with custom scheme.
            // Replace "https://" with "youtube-proxy://" — this forces AVPlayer
            // to route ALL requests through our delegate, where we inject headers.
            let proxyURLString = streamURL.replacingOccurrences(of: "https://", with: "youtube-proxy://")
            guard let proxyURL = URL(string: proxyURLString) else {
                print("⚠️ v91: Failed to create proxy URL")
                return
            }

            let loaderDelegate = YouTubeResourceLoaderDelegate(originalURL: url, cookies: cookies)
            resourceLoaderDelegate = loaderDelegate

            let urlAsset = AVURLAsset(url: proxyURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
            urlAsset.resourceLoader.setDelegate(loaderDelegate, queue: loaderDelegate.queue)
            asset = urlAsset
            print("🎬 v91: googlevideo.com URL — AVAssetResourceLoaderDelegate attached (custom scheme: youtube-proxy://)")
        } else {
            asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
        }

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
