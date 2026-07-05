import Foundation
import Network

// MARK: - PlinkLocalServer (v23)
//
// Local HTTP server on localhost — serves YouTube player HTML.
// iOS allows http://localhost without ATS restrictions (no SSL needed).
// This bypasses ALL sandbox/ATS issues:
//   - No "Could not create a sandbox extension" (localhost is trusted)
//   - No DownloadFailed (no cross-origin HTTPS to plink.app)
//   - No TCP Reset (localhost is internal, no network interference)
//   - YouTube gets Origin/Referer from the iframe params (hardcoded plink.app)

final class PlinkLocalServer {
    static let shared = PlinkLocalServer()
    private var listener: NWListener?
    private(set) var port: UInt16 = 8080

    private init() {}

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

    func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        do {
            listener = try NWListener(using: parameters, on: nwPort)
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed:
                    self?.retryWithRandomPort()
                case .ready:
                    print("🚀 PlinkLocalServer: running on http://localhost:\(self?.port ?? 8080)")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: DispatchQueue.global(qos: .userInitiated))
        } catch {
            print("❌ PlinkLocalServer: failed to start on port \(port): \(error)")
            retryWithRandomPort()
        }
    }

    private func retryWithRandomPort() {
        listener?.cancel()
        listener = nil
        port = UInt16.random(in: 49152...65535)
        start()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .utility))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, error in
            guard let data = data,
                  let requestStr = String(data: data, encoding: .utf8),
                  error == nil else {
                connection.cancel()
                return
            }

            // Parse video ID from GET request: "GET /?v=VIDEO_ID HTTP/1.1"
            let videoId = requestStr.components(separatedBy: "v=").last?
                .components(separatedBy: " ").first ?? ""
            let html = self?.getPlayerHTML(for: videoId) ?? ""

            let httpResponse = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(html.utf8.count)\r
            Connection: close\r
            \r
            \(html)
            """

            if let responseData = httpResponse.data(using: .utf8) {
                connection.send(content: responseData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                connection.cancel()
            }
        }
    }
}
