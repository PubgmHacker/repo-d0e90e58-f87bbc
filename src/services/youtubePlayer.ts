// GET /api/media/youtube-player?id=VIDEO_ID — Hosted YouTube IFrame Player
//
// v11 (July 2026): serves a static HTML page that uses YouTube IFrame API.
// iOS loads this URL via webView.load(URLRequest(url: backendURL)).
//
// WHY THIS WORKS (where all previous approaches failed):
//   - v1-v7: loadHTMLString → null origin → IFrame API postMessage fails (152-4)
//   - v8-v9: backend extraction → yt-dlp blocked on Railway IP
//   - v10.x: direct embed URL in WKWebView → YouTube detects WKWebView (153)
//
//   v11: hosted HTML page has REAL origin (https://plink-backend...).
//   IFrame API postMessage works (parent page has real origin).
//   YouTube's WKWebView detection doesn't run (player JS runs in our
//   page context, not YouTube's embed page).
//   No customUserAgent needed (backend serves the page, not YouTube).
//
// The HTML page:
//   1. Loads YouTube IFrame API script
//   2. Creates a YT.Player with the video ID
//   3. Player fills 100% of the viewport
//   4. Autoplay on ready (muted first, then unmute — iOS requires user gesture
//      for unmuted autoplay, but muted autoplay works)
//   5. Plink's WKWebView shows this page — YouTube's player runs inside an
//      iframe, but the PARENT page is our backend (real origin), not WKWebView.

export function youtubePlayerHTML(videoId: string): string {
  return `<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
        #player { width: 100vw; height: 100vh; }
        iframe { width: 100% !important; height: 100% !important; border: none; }
    </style>
</head>
<body>
    <div id="player"></div>
    <script src="https://www.youtube.com/iframe_api"></script>
    <script>
        var player;
        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                videoId: '${videoId}',
                playerVars: {
                    'playsinline': 1,
                    'rel': 0,
                    'modestbranding': 1,
                    'fs': 0,
                    'controls': 1,
                    'iv_load_policy': 3
                },
                events: {
                    'onReady': function(e) {
                        // Muted autoplay (iOS requires user gesture for unmuted)
                        player.mute();
                        player.playVideo();
                        // Try to unmute after 1 second
                        setTimeout(function() {
                            player.unMute();
                        }, 1000);
                    },
                    'onStateChange': function(e) {
                        // state 0 = ended → seek to 0 to prevent end-screen
                        if (e.data === 0) {
                            player.seekTo(0, true);
                            player.pauseVideo();
                        }
                    }
                }
            });
        }
    </script>
</body>
</html>`;
}
