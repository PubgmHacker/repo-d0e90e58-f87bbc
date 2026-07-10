// Plink/Playback/Providers/YouTubeEmbeddedProvider.swift
// App Store compliant YouTube provider (runbook §7)
//
// CRITICAL DIFFERENCE from legacy YouTube flow:
//
//   LEGACY (forbidden — runbook §7):
//     - Server-side extraction via Innertube API with user cookies
//     - yt-dlp / Piped fallback
//     - Cookie relay from iOS WebView → backend → googlevideo CDN
//     - Raw CDN proxy through /api/media/stream
//     - All of these violate YouTube ToS and Apple App Store Review Guideline
//       4.2 (minimum functionality) and 5.6 (content extraction).
//
//   v2 (THIS FILE — App Store compliant):
//     - Use the OFFICIAL YouTube IFrame Player API inside a WKWebView.
//     - The WebView is owned by this provider (NOT a global singleton — §16).
//     - NO cookies leave the device.
//     - NO server-side extraction.
//     - NO raw CDN proxy.
//     - YouTube branding and controls remain visible (per YouTube ToS).
//     - Sync control via JS bridge (play/pause/seek) — limited rate
//       correction (no setRate on IFrame API for non-PRO content).
//
// Capabilities reported:
//   - seekable: true (via JS bridge seekTo)
//   - supportsPiP: false (IFrame player does not support PiP reliably)
//   - supportsAirPlay: false (IFrame player uses its own AirPlay UI)
//   - supportsRateCorrection: false — OrderedSyncController falls back to
//     less frequent precise seeks (§19)
//   - supportsDRM: false

import Foundation
import UIKit
import WebKit

@MainActor
public final class YouTubeEmbeddedProvider: NSObject, ProviderAdapter {
    public private(set) var playerItem: AVPlayerItem? { nil }
    public private(set) var embeddedView: UIView?

    public var capabilities: PlaybackCapabilities {
        .init(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    private var webView: WKWebView?
    private var videoId: String?

    public override init() {
        super.init()
    }

    public func prepare(source: PlaybackSource) async throws {
        guard case .youtube(let id) = source else {
            throw ProviderError.unsupportedSource
        }
        self.videoId = id

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Per §19: persistent store only with explicit product reason. The
        // embedded YouTube player needs login state to access age-restricted
        // content, so we use the default (persistent) store — but provide
        // a logout/clear-data path in WatchRoomModel.
        // (nonPersistent would force login on every launch.)
        let web = WKWebView(frame: .zero, configuration: config)
        web.translatesAutoresizingMaskIntoConstraints = false
        self.webView = web
        self.embeddedView = web

        // Load IFrame API with videoId. Controls=1 keeps YouTube branding
        // visible (ToS requirement).
        let html = """
        <!DOCTYPE html>
        <html>
          <body style="margin:0;background:#000;">
            <div id="player"></div>
            <script>
              var tag = document.createElement('script');
              tag.src = "https://www.youtube.com/iframe_api";
              var firstScriptTag = document.getElementsByTagName('script')[0];
              firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
              var ytPlayer;
              function onYouTubeIframeAPIReady() {
                ytPlayer = new YT.Player('player', {
                  videoId: '\(id)',
                  playerVars: {
                    'controls': 1,
                    'modestbranding': 1,
                    'playsinline': 1,
                    'rel': 0
                  },
                  events: {
                    'onReady': function() {
                      window.webkit.messageHandlers.player.postMessage({event:'ready'});
                    },
                    'onStateChange': function(e) {
                      window.webkit.messageHandlers.player.postMessage({
                        event:'stateChange', state:e.data
                      });
                    }
                  }
                });
              }
              window.webkit = window.webkit || { messageHandlers: { player: { postMessage: function(){} } } };
            </script>
          </body>
        </html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    public func teardown() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        embeddedView = nil
        videoId = nil
    }
}
