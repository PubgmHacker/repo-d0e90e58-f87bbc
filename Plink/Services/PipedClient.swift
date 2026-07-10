import Foundation

// MARK: - PipedClient (v93 — API Gateway for YouTube stream extraction)
//
// 🔧 v93 (Gemini): Piped API client with automatic failover.
// Piped is a public API that extracts direct stream URLs from YouTube
// WITHOUT requiring BotGuard bypass on the client. It runs on multiple
// public instances — if one is down, we try the next.
//
// API: GET https://<instance>/streams/<videoId>
// Response JSON: { "hls": "...", "videoStreams": [...], "audioStreams": [...] }
//
// Strategy:
//   1. Try each Piped instance in order
//   2. First successful response → extract stream URL
//   3. Priority: muxed MP4 (video+audio) > HLS manifest
//   4. If all instances fail → fallback to ExtractionBridge (WKWebView scraper)

@MainActor
final class PipedClient {

    static let shared = PipedClient()

    /// Public Piped instances — tried in order for failover.
    /// These are public community-maintained instances.
    /// If one is down/rate-limited, we move to the next.
    private let instances = [
        "https://pipedapi.kavin.rocks",
        "https://api.piped.yt",
        "https://pipedapi.moomoo.me",
        "https://pipedapi.leptons.xyz",
        "https://pipedapi.tokhmi.xyz",
        "https://pipedapi.silkky.cloud",
        "https://pipedapi.r4fo.com",
    ]

    private init() {}

    // MARK: - Stream Info

    struct StreamInfo {
        let streamURL: String
        let title: String
        let duration: TimeInterval
        let isHLS: Bool
    }

    enum PipedError: LocalizedError {
        case allInstancesFailed
        case noStreamFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .allInstancesFailed: return "Все Piped инстансы недоступны"
            case .noStreamFound: return "Поток не найден в ответе Piped"
            case .invalidResponse: return "Неверный ответ от Piped API"
            }
        }
    }

    // MARK: - Extract

    /// Extract stream URL from YouTube via Piped API.
    /// Tries each instance in order until one succeeds.
    /// Returns StreamInfo with direct googlevideo.com URL for AVPlayer.
    func extract(videoId: String) async throws -> StreamInfo {
        print("🌐 v93: PipedClient — extracting videoId='\(videoId)'")

        var lastError: Error?

        for (index, instance) in instances.enumerated() {
            do {
                let streamInfo = try await extractFromInstance(
                    instance: instance, videoId: videoId, index: index
                )
                return streamInfo
            } catch {
                print("⚠️ v93: Piped instance #\(index) (\(instance)) failed: \(error.localizedDescription)")
                lastError = error
                // Continue to next instance
            }
        }

        // All instances failed
        print("❌ v93: All \(instances.count) Piped instances failed")
        throw lastError ?? PipedError.allInstancesFailed
    }

    // MARK: - Single Instance Request

    private func extractFromInstance(
        instance: String,
        videoId: String,
        index: Int
    ) async throws -> StreamInfo {
        let urlString = "\(instance)/streams/\(videoId)"
        guard let url = URL(string: urlString) else {
            throw PipedError.invalidResponse
        }

        print("🌐 v93: Trying instance #\(index): \(instance)/streams/\(videoId)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10s per instance
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PipedError.invalidResponse
        }

        // Parse JSON response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PipedError.invalidResponse
        }

        let title = json["title"] as? String ?? ""
        let duration = (json["duration"] as? Double) ?? 0

        // Priority 1: Muxed video streams (video+audio in one file = AVPlayer friendly)
        if let videoStreams = json["videoStreams"] as? [[String: Any]] {
            // Find muxed MP4 (type == "MUTED" or has both video+audio)
            // itag 22 = 720p MP4 muxed, itag 18 = 360p MP4 muxed
            let muxedStreams = videoStreams.filter { stream in
                let videoOnly = stream["videoOnly"] as? Bool ?? true
                return !videoOnly  // muxed = NOT videoOnly
            }

            // Try itag 22 (720p) first, then itag 18 (360p), then first muxed
            let best = muxedStreams.first(where: { ($0["itag"] as? Int) == 22 })
                       ?? muxedStreams.first(where: { ($0["itag"] as? Int) == 18 })
                       ?? muxedStreams.first

            if let stream = best,
               let streamURL = stream["url"] as? String {
                print("✅ v93: Piped — found muxed MP4 (itag=\(stream["itag"] ?? "?")) from instance #\(index)")
                return StreamInfo(
                    streamURL: streamURL,
                    title: title,
                    duration: duration,
                    isHLS: false
                )
            }
        }

        // Priority 2: HLS manifest URL
        if let hlsURL = json["hls"] as? String, !hlsURL.isEmpty {
            print("✅ v93: Piped — found HLS manifest from instance #\(index)")
            return StreamInfo(
                streamURL: hlsURL,
                title: title,
                duration: duration,
                isHLS: true
            )
        }

        // No usable stream found
        throw PipedError.noStreamFound
    }
}
