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
        let rawVideoId = components?.queryItems?.first(where: { $0.name == "v" })?.value ?? ""

        // 🔧 v29.1 (July 2026): SANITIZE video ID — defense in depth.
        //
        // Even though RoomSetupView v29 now correctly extracts the 11-char
        // video ID, we ALSO sanitize here as a safety net. If anything in
        // the pipeline (backend, sync engine, room restoration from DB)
        // ever passes a malformed string like:
        //   - "watch?v=fDJ38th1G9w"
        //   - "embed/fDJ38th1G9w"
        //   - "https://youtube.com/watch?v=fDJ38th1G9w"
        //   - "fDJ38th1G9w&t=10s"
        // we extract the clean 11-char video ID before building the iframe URL.
        //
        // Without this, a single bad videoId propagates to the iframe src
        // as youtube-nocookie.com/embed/watch?v=fDJ38th1G9w → YouTube
        // returns error 153 (treats it as spoofing attempt).
        let videoId = Self.sanitizeVideoId(rawVideoId)
        if videoId != rawVideoId {
            print("🧹 PlinkSchemeHandler v29.1: sanitized videoId '\(rawVideoId)' → '\(videoId)'")
        }

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

    // MARK: - Video ID Sanitizer (v29.1)

    /// 🔧 v29.1: Extract a clean 11-char YouTube video ID from ANY string
    /// that might contain one. Defense in depth — if anything in the
    /// pipeline passes a malformed value, we clean it here before building
    /// the iframe src URL.
    ///
    /// Handles these input formats (and returns the clean ID):
    ///   "fDJ38th1G9w"                          → "fDJ38th1G9w"  (already clean)
    ///   "watch?v=fDJ38th1G9w"                  → "fDJ38th1G9w"
    ///   "embed/fDJ38th1G9w"                    → "fDJ38th1G9w"
    ///   "https://youtube.com/watch?v=fDJ38th1G9w"        → "fDJ38th1G9w"
    ///   "https://youtu.be/fDJ38th1G9w"                   → "fDJ38th1G9w"
    ///   "https://youtube-nocookie.com/embed/fDJ38th1G9w" → "fDJ38th1G9w"
    ///   "fDJ38th1G9w&t=10s"                    → "fDJ38th1G9w"
    ///   "fDJ38th1G9w?si=abc"                   → "fDJ38th1G9w"
    ///   "" or "garbage"                        → ""  (empty, caller handles)
    static func sanitizeVideoId(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Case 1: full URL — parse via URLComponents
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let url = URL(string: trimmed),
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                // youtube.com/watch?v=ID
                if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
                   !v.isEmpty {
                    return Self.cleanId(v)
                }
                // youtu.be/ID or /embed/ID or /shorts/ID
                let segments = url.path.split(separator: "/").map(String.init)
                if let last = segments.last, last != "watch", last.count >= 6 {
                    return Self.cleanId(last)
                }
            }
            return ""
        }

        // Case 2: contains "watch?v=ID" or "v=ID"
        if trimmed.contains("v=") {
            // Extract everything after "v=" up to "&" or end
            if let vStart = trimmed.range(of: "v=") {
                let afterV = String(trimmed[vStart.upperBound...])
                let id = afterV.components(separatedBy: "&").first ?? afterV
                return Self.cleanId(id)
            }
        }

        // Case 3: contains "embed/ID"
        if trimmed.contains("embed/") {
            let afterEmbed = trimmed.components(separatedBy: "embed/").last ?? trimmed
            let id = afterEmbed.components(separatedBy: "?").first ?? afterEmbed
            return Self.cleanId(id)
        }

        // Case 4: already a clean ID (possibly with trailing ? or & params)
        return Self.cleanId(trimmed)
    }

    /// Strip query params, trailing slashes, and validate length.
    /// YouTube video IDs are exactly 11 chars: [A-Za-z0-9_-]
    private static func cleanId(_ s: String) -> String {
        var id = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip anything after ? or & or /
        if let cut = id.firstIndex(where: { $0 == "?" || $0 == "&" || $0 == "/" }) {
            id = String(id[..<cut])
        }
        // Validate: 11 chars, [A-Za-z0-9_-]
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard id.count == 11, id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            // Not a valid 11-char ID — return what we have, caller will handle
            return id
        }
        return id
    }
}
