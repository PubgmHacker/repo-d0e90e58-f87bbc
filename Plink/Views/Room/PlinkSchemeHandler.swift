import WebKit

// MARK: - PlinkSchemeHandler (v24)
//
// WKURLSchemeHandler — intercepts custom URL scheme "plink-media://" 
// and serves YouTube player HTML directly from memory.
//
// No network requests → no sandbox issues → no ATS → no DownloadFailed.
// The URL scheme host is "plink.app" so YouTube's player JS sees a
// legitimate domain (not localhost).
//
// YouTube iframe inside the HTML still loads from youtube-nocookie.com
// (real HTTPS), with origin=https://plink.app in the URL params.

final class PlinkSchemeHandler: NSObject, WKURLSchemeHandler {

    func getPlayerHTML(for videoId: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: #000; }
                iframe { width: 100%; height: 100%; border: 0; }
            </style>
        </head>
        <body>
            <iframe
                id="player"
                src="https://www.youtube-nocookie.com/embed/\(videoId)?enablejsapi=1&playsinline=1&controls=0&rel=0&modestbranding=1&iv_load_policy=3&origin=https://plink.app&widget_referrer=https://plink.app"
                allow="autoplay; encrypted-media"
                referrerpolicy="strict-origin-when-cross-origin"
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // 🔧 v24.2: ignore sub-resource requests (favicon, css, images)
        // YouTube's iframe might try to load these through our scheme.
        // Return empty 200 to prevent network errors.
        let path = url.path.lowercased()
        if path.contains("favicon") || path.hasSuffix(".css") || path.hasSuffix(".png")
            || path.hasSuffix(".ico") || path.hasSuffix(".js") {
            let response = URLResponse(url: url, mimeType: "text/plain",
                                       expectedContentLength: 0, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }

        // Parse video ID from URL: plink-media://plink.app/?v=VIDEO_ID
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let videoId = components?.queryItems?.first(where: { $0.name == "v" })?.value ?? ""

        let htmlString = getPlayerHTML(for: videoId)
        guard let data = htmlString.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(URLError(.cannotDecodeContentData))
            return
        }

        // Create HTTP-like response with the same URL (host = plink.app)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Called when the request is cancelled — nothing to clean up.
    }
}
