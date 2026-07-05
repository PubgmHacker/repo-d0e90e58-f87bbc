// v18.2: No host:nocookie — use default YouTube domain (avoids CSP frame-src issues)
// + inline CSP meta tag as fallback in case backend headers don't apply

export function youtubePlayerHTML(videoId: string): string {
  return `<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <!-- CSP: allow YouTube scripts + iframes from both youtube.com and youtube-nocookie.com -->
    <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; script-src * 'unsafe-inline' 'unsafe-eval'; style-src * 'unsafe-inline'; img-src * data: blob:; media-src *; connect-src * wss:; frame-src *; child-src *;">
    <style>
        body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: #000; }
        #player { width: 100%; height: 100%; }
        iframe { width: 100% !important; height: 100% !important; border: 0; }
    </style>
</head>
<body>
    <div id="player"></div>

    <script>
        // Load YouTube IFrame API
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

        var player;
        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                height: '100%',
                width: '100%',
                videoId: '${videoId}',
                // 🔧 v18.2: REMOVED host:'https://www.youtube-nocookie.com'
                // host:nocookie caused CSP frame-src conflicts. Default host
                // (youtube.com) works fine when page has real HTTPS origin.
                playerVars: {
                    'playsinline': 1,
                    'controls': 0,
                    'rel': 0,
                    'modestbranding': 1,
                    'iv_load_policy': 3,
                    'origin': window.location.origin
                },
                events: {
                    'onReady': function(event) {
                        // Muted autoplay (iOS requirement), unmute after 1s
                        player.mute();
                        player.playVideo();
                        setTimeout(function() {
                            player.unMute();
                        }, 1000);
                        console.log("PlinkPlayerReady");
                    },
                    'onStateChange': function(event) {
                        // state 0 = ended → seek to 0 to prevent end-screen
                        if (event.data === 0) {
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
