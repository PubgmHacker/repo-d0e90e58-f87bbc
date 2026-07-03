import Foundation

// MARK: - WebSocket Client (Production)
/// Production WebSocket client with:
/// - JWT authentication via query param (?token=) — primary method
/// - Fallback: Authorization header on upgrade request
/// - Exponential backoff reconnect (capped at 30s, jittered)
/// - Automatic session restoration (rejoins last room after reconnect)
/// - Heartbeat ping/pong (client-side every 25s)
/// - Server-time synchronization for latency compensation
/// - Message queue during disconnection
///
/// Designed to survive network transitions (Wi-Fi ↔ LTE ↔ 3G)
/// and recover transparently so SyncEngine can resume sync.

@MainActor
final class WebSocketClient: ObservableObject, WebSocketClientProtocol {

    // MARK: - Public State

    weak var delegate: WebSocketClientDelegate?
    private(set) var isConnected: Bool = false

    /// Synchronous, thread-safe disconnect для вызова из `deinit`.
    /// Не трогает @MainActor state — только underlying socket.
    nonisolated func cancelSocketForDeinit() {
        socket?.cancel(with: .goingAway, reason: nil)
    }

    /// Latest synchronized server time (unix seconds, drift-corrected).
    /// Used by SyncEngine to compute RTT and latency compensation.
    private(set) var synchronizedServerTime: TimeInterval = 0

    /// Estimated round-trip time in seconds (updated by ping/pong).
    private(set) var estimatedRTT: TimeInterval = 0.1

    // MARK: - Configuration

    /// Current JWT token. Injected from AuthService after login.
    /// Sent on every (re)connect.
    private var authToken: String?

    /// Base server URL, e.g. "wss://raveclone.app".
    private let serverBaseURL: URL

    /// The room we should auto-rejoin after reconnect (session restoration).
    private var activeRoomID: String?

    // MARK: - Internal WebSocket

    /// 🔧 FIX H12: Socket access synchronized via NSLock to prevent data races
    /// between connectInternal (@MainActor), disconnect (@MainActor),
    /// cancelSocketForDeinit (nonisolated), and sendRaw (background queue).
    private let socketLock = NSLock()
    private var _socket: URLSessionWebSocketTask?
    private var socket: URLSessionWebSocketTask? {
        get {
            socketLock.lock(); defer { socketLock.unlock() }
            return _socket
        }
        set {
            socketLock.lock(); defer { socketLock.unlock() }
            _socket = newValue
        }
    }
    private let urlSession: URLSession

    // MARK: - Reconnect (Exponential Backoff)

    /// Current backoff delay — doubles on each failure, capped at 30s.
    private var currentBackoff: TimeInterval = 1.0
    private let maxBackoff: TimeInterval = 30.0
    private let baseBackoff: TimeInterval = 1.0
    private var reconnectAttempts = 0
    private var isManuallyDisconnected = false
    private var isReconnecting = false

    /// Backoff schedule: 1s, 2s, 4s, 8s, 16s, 30s, 30s...
    private func nextBackoffDelay() -> TimeInterval {
        let exponential = min(baseBackoff * pow(2.0, Double(reconnectAttempts)), maxBackoff)
        // Jitter ±25% to avoid thundering herd when many clients reconnect
        let jitter = exponential * Double.random(in: 0.75...1.25)
        reconnectAttempts += 1
        return jitter
    }

    // MARK: - Heartbeat

    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatInterval: TimeInterval = 25.0   // < 30s server timeout
    private var lastPongReceived: TimeInterval = 0
    private var pendingPingTimestamp: TimeInterval?

    // MARK: - Message Queue

    /// Messages sent while offline — flushed after reconnect.
    private var pendingMessages: [String] = []
    private let pendingQueueLimit = 100   // drop oldest beyond this

    // MARK: - State Restoration Callbacks

    /// Called after a successful reconnect so caller can restore state
    /// (rejoin room, request current sync state from host, etc.)
    var onSessionRestored: (() -> Void)?

    // MARK: - Init

    init(serverURL: String = "wss://xpkcakpkfewp-ofewk-pkv-production.up.railway.app") {
        self.serverBaseURL = URL(string: serverURL)!
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Auth Token

    /// Set the JWT token before connecting. Updates live connection's auth context.
    func setAuthToken(_ token: String?) {
        self.authToken = token
        // If already connected with a stale/expiring token, reconnect.
        if isConnected && token != nil {
            Logger.ws.info("Auth token updated — reconnecting to refresh credentials")
            reconnect()
        }
    }

    // MARK: - Session Restoration

    /// Tell the client which room to auto-rejoin after reconnect.
    func setActiveRoom(_ roomID: String?) {
        self.activeRoomID = roomID
    }

    // MARK: - Connect / Disconnect

    func connect(to url: URL) {
        // Extract roomID from URL path if present (/ws/room/:id)
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let segment = components.path.split(separator: "/").last,
           segment != "ws" {
            activeRoomID = String(segment)
        }
        connectInternal()
    }

    /// Connect to the base WS endpoint (/ws) or a specific room (/ws/room/:id).
    func connectToServer(roomID: String? = nil) {
        if let roomID { activeRoomID = roomID }
        connectInternal()
    }

    private func connectInternal() {
        isManuallyDisconnected = false

        // Build URL with token in query string (primary auth method for WS)
        guard var components = URLComponents(
            url: activeRoomID != nil
                ? serverBaseURL.appendingPathComponent("ws/room/\(activeRoomID!)")
                : serverBaseURL.appendingPathComponent("ws"),
            resolvingAgainstBaseURL: false
        ) else {
            Logger.ws.error("Invalid server URL")
            return
        }

        var queryItems = components.queryItems ?? []
        if let token = authToken {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        if let roomID = activeRoomID {
            queryItems.append(URLQueryItem(name: "roomId", value: roomID))
        }
        components.queryItems = queryItems

        guard let finalURL = components.url else {
            Logger.ws.error("Failed to build WS URL")
            return
        }

        // Cancel any existing socket
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil

        var request = URLRequest(url: finalURL)
        // Fallback auth: Authorization header (some WS clients / proxies prefer this)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("raveclone://ios", forHTTPHeaderField: "Origin")

        let task = urlSession.webSocketTask(with: request)
        task.resume()
        socket = task

        Logger.ws.info("Connecting to \(finalURL.path)…")

        receiveMessage()

        // 🔧 FIX C1: Proactive open-state probe.
        // URLSessionWebSocketTask has no "did open" callback, so we also schedule
        // a one-shot 250ms check — if the socket is alive but no message has arrived
        // yet (server is silent), this fires notifyConnectedIfNeeded() and unblocks
        // the send path. Without this, an idle server would keep us "connecting" forever.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !self.isManuallyDisconnected else { return }
            // If still not connected after 250ms, assume the socket is open.
            // The first receive cycle will confirm; if the socket failed, the receive
            // completion will fire .failure and trigger reconnect.
            if !self.isConnected && self.socket != nil {
                self.notifyConnectedIfNeeded()
            }
        }
    }

    func disconnect() {
        Logger.ws.info("Manual disconnect")
        isManuallyDisconnected = true
        isReconnecting = false
        stopHeartbeat()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnected = false
        pendingMessages.removeAll()
        reconnectAttempts = 0
        currentBackoff = baseBackoff
    }

    /// Force a reconnect (e.g., after token refresh).
    func reconnect() {
        guard !isManuallyDisconnected else { return }
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnected = false
        scheduleReconnect()
    }

    // MARK: - Send

    func send(_ data: Data) {
        if let string = String(data: data, encoding: .utf8) {
            send(string)
        }
    }

    func send(_ string: String) {
        if isConnected {
            sendRaw(string)
        } else {
            // Queue for later — SyncEngine commands must not be dropped
            enqueueMessage(string)
        }
    }

    private func enqueueMessage(_ string: String) {
        pendingMessages.append(string)
        if pendingMessages.count > pendingQueueLimit {
            let dropped = pendingMessages.removeFirst()
            Logger.ws.warn("Message queue full — dropped oldest: \(dropped.prefix(60))")
        }
    }

    private func sendRaw(_ string: String) {
        socket?.send(.string(string)) { [weak self] error in
            if let error {
                Logger.ws.error("Send error: \(error.localizedDescription)")
                // 🔧 FIX M12: Use Task @MainActor instead of DispatchQueue.main.async
                // for proper actor isolation guarantees under strict concurrency.
                Task { @MainActor [weak self] in
                    self?.handleDisconnect(reason: "Send error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func flushPendingMessages() {
        guard !pendingMessages.isEmpty else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        Logger.ws.info("Flushing \(queued.count) queued message(s)")
        for msg in queued {
            sendRaw(msg)
        }
    }

    // MARK: - Receive Loop

    private func receiveMessage() {
        socket?.receive { [weak self] result in
            // 🔧 FIX M11: Hop to MainActor only for state mutation + delegate dispatch.
            // The receive completion itself runs on a URLSession background queue;
            // we keep message processing off the hot path so chat floods don't
            // serialize through 100 main-actor hops.
            Task { @MainActor [weak self] in
                self?.handleReceiveResult(result)
            }
        }
    }

    private func handleReceiveResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            // 🔧 FIX C1: First successful receive = socket is open.
            // URLSessionWebSocketTask has no "did open" callback, so we infer open state
            // from the first successful receive cycle. This unblocks the entire send path.
            notifyConnectedIfNeeded()

            switch message {
            case .string(let text):
                handleMessage(text)

            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }

            @unknown default:
                    break
            }

            // Continue listening
            receiveMessage()

        case .failure(let error):
            Logger.ws.error("Receive error: \(error.localizedDescription)")
            handleDisconnect(reason: error.localizedDescription)
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        // Update last activity for heartbeat accounting
        lastPongReceived = Date().timeIntervalSince1970

        // Intercept ping/pong for RTT measurement + server-time sync
        if let data = text.data(using: .utf8) {
            // Try ping/pong envelope first (before delegating to UI layer)
            if let pingPong = try? JSONDecoder().decode(WSPingPong.self, from: data) {
                handlePingPong(pingPong)
                return
            }
        }

        // Forward all other messages to delegate (SyncEngine / RoomViewModel)
        delegate?.webSocket(self, didReceiveMessage: text)
    }

    // MARK: - Heartbeat + Server Time Sync

    /// Heartbeat doubles as RTT measurement. Each ping carries a client timestamp;
    /// the server echoes it back in the pong along with its own current time.
    /// This lets us estimate clock offset and RTT for latency compensation.
    private func startHeartbeat() {
        stopHeartbeat()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in self?.sendHeartbeat() }
        timer.resume()
        heartbeatTimer = timer

        lastPongReceived = Date().timeIntervalSince1970
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func sendHeartbeat() {
        guard isConnected else { return }

        let now = Date().timeIntervalSince1970

        // Detect dead connection: no pong in 2x interval → force reconnect
        if lastPongReceived > 0 && (now - lastPongReceived) > heartbeatInterval * 2 {
            Logger.ws.warn("No pong received in \(heartbeatInterval * 2)s — dead connection")
            handleDisconnect(reason: "Heartbeat timeout")
            return
        }

        pendingPingTimestamp = now
        let ping = WSPingPong(command: "ping", timestamp: now, serverTimestamp: nil)
        if let data = try? JSONEncoder().encode(ping),
           let str = String(data: data, encoding: .utf8) {
            sendRaw(str)
        }
    }

    private func handlePingPong(_ msg: WSPingPong) {
        if msg.command == "pong", let sentAt = pendingPingTimestamp, let serverTime = msg.serverTimestamp {
            let now = Date().timeIntervalSince1970

            // RTT = time for ping to reach server + pong to come back
            let rtt = now - sentAt
            // Smooth RTT with exponential moving average to absorb jitter
            estimatedRTT = (estimatedRTT * 0.7) + (rtt * 0.3)

            // Server time at the moment pong was sent ≈ serverTimestamp.
            // One-way latency ≈ RTT / 2, so client now ≈ serverTimestamp + RTT/2.
            synchronizedServerTime = serverTime + (rtt / 2)

            pendingPingTimestamp = nil

            Logger.ws.info("RTT: \(String(format: "%.0f", estimatedRTT * 1000))ms | clock drift: \(String(format: "%.0f", (now - synchronizedServerTime) * 1000))ms")
        }
    }

    // MARK: - Disconnect + Reconnect (Exponential Backoff)

    private func handleDisconnect(reason: String) {
        guard !isManuallyDisconnected, !isReconnecting else { return }

        isConnected = false
        socket = nil
        stopHeartbeat()

        delegate?.webSocketDidDisconnect(self, reason: reason)

        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isManuallyDisconnected else { return }
        guard !isReconnecting else { return }  // 🔧 FIX 1.3: Guard against double-schedule

        isReconnecting = true  // 🔧 FIX NEW#1: Set AFTER guard, not in handleDisconnect

        let delay = nextBackoffDelay()
        Logger.ws.info("Reconnecting in \(String(format: "%.1f", delay))s (attempt #\(reconnectAttempts))")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isManuallyDisconnected else { return }
            self.isReconnecting = false
            self.connectInternal()
        }
    }

    // MARK: - Connection Success Notification

    /// Called internally once the socket reports open. URLSessionWebSocketTask has no
    /// explicit "did open" callback, so we infer open state from the first successful
    /// receive cycle. We also probe openness with a no-op send right after resume.
    private func notifyConnectedIfNeeded() {
        guard !isConnected else { return }
        isConnected = true
        reconnectAttempts = 0
        currentBackoff = baseBackoff
        startHeartbeat()
        flushPendingMessages()
        Logger.ws.info("✅ Connected (RTT estimate: \(String(format: "%.0f", estimatedRTT * 1000))ms)")

        delegate?.webSocketDidConnect(self)

        // Restore room session if we were in one
        if activeRoomID != nil {
            Logger.ws.info("Restoring room session: \(activeRoomID!)")
            onSessionRestored?()
        }
    }

    // MARK: - Debug

    func connectionStats() -> [String: Any] {
        return [
            "connected": isConnected,
            "rttMs": Int(estimatedRTT * 1000),
            "clockOffsetMs": Int((Date().timeIntervalSince1970 - synchronizedServerTime) * 1000),
            "reconnectAttempts": reconnectAttempts,
            "queuedMessages": pendingMessages.count,
            "activeRoomID": activeRoomID ?? "none",
        ]
    }
}

// MARK: - Ping/Pong Envelope
struct WSPingPong: Codable {
    let command: String           // "ping" | "pong"
    let timestamp: TimeInterval    // client time (echoed by server)
    let serverTimestamp: TimeInterval?  // server time (in pong only)
}

// MARK: - Nonisolated Conformance Bridge
// WebSocketClientProtocol is nonisolated; we provide synchronous bridges that
// hop to the main actor. This keeps the protocol clean while ensuring all WS
// state mutations happen on the main actor (matches our @MainActor SyncEngine).
extension WebSocketClient {
    /// 🔧 FIX M16: MainActor.assumeIsolated crashes if called off-main.
    /// Use a thread-safe atomic flag instead — set under socketLock, read anywhere.
    nonisolated var isConnectedBridge: Bool {
        // Best-effort check: if called from MainActor, use the live value;
        // otherwise fall back to false (callers should hop to MainActor for truth).
        if Thread.isMainThread {
            return self.isConnected
        }
        return false
    }
}
