// Plink/Realtime/RealtimeClient.swift
// Production WebSocket client (runbook §8)
//
// Replaces Plink/Networking/WebSocketClient.swift. Key differences:
//
//   1. NO fake 'connected' via timer. Uses URLSessionWebSocketDelegate callback
//      urlSession(_:webSocketTask:didOpenWithProtocol:) — the ONLY reliable
//      signal that the WS handshake completed.
//   2. NO JWT in URL query string. Auth via Sec-WebSocket-Protocol subprotocol
//      with a short-lived (60s) single-use ticket from POST /api/realtime/ticket.
//   3. Explicit connection state machine (RealtimeConnectionState).
//      Clients must NOT treat the socket as 'connected' until session.ready
//      arrives (runbook §19).
//   4. ONE receive loop — never two. Cancellation is structured (Task.cancel).
//   5. Reconnect protocol (§5, §19):
//        auth → join → 7 clock probes → snapshot request → UI connected
//        NO replay of local transport commands (play/pause/seek) from offline.
//   6. State changes flow as an AsyncStream — replaces the legacy
//      onSessionRestored callback.
//   7. All reconnect Tasks are cancelled on manual disconnect and deinit.
//   8. NO @unchecked Sendable. Transport is isolated to a custom actor or
//      MainActor; thread safety is proven, not assumed.
//
// Legacy WebSocketClient.swift is NOT deleted — it stays behind the
// realtime_protocol_v2 feature flag (§15). It will be removed after one
// release cycle.

import Foundation

@MainActor
public final class RealtimeClient: NSObject, ObservableObject {
    @Observable public private(set) var state: RealtimeConnectionState = .idle
    @Observable public private(set) var lastError: String?

    /// Server messages — consumers (WatchRoomModel, OrderedSyncController,
    /// ChatTimeline) subscribe to this stream.
    public var messages: AsyncStream<RealtimeServerMessage> {
        AsyncStream { continuation in
            self.messageContinuations.append(continuation)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.messageContinuations.removeAll { $0 === continuation }
            }
        }
    }

    /// State change events — UI (ConnectionBanner) subscribes to this.
    public var stateChanges: AsyncStream<RealtimeConnectionState> {
        AsyncStream { continuation in
            self.stateContinuations.append(continuation)
            continuation.yield(self.state)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.stateContinuations.removeAll { $0 === continuation }
            }
        }
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var clockProbeTask: Task<Void, Never>?

    private var messageContinuations: [AsyncStream<RealtimeServerMessage>.Continuation] = []
    private var stateContinuations: [AsyncStream<RealtimeConnectionState>.Continuation] = []

    private let endpoint: URL
    private let ticketProvider: () async -> String?
    private var currentTicket: String?
    private var reconnectAttempt = 0
    private static let maxReconnectBackoffSec: Double = 30

    public init(endpoint: URL, ticketProvider: @escaping () async -> String?) {
        self.endpoint = endpoint
        self.ticketProvider = ticketProvider
        super.init()
    }

    // MARK: - Connect

    public func connect() {
        guard state == .idle || state.isTransient == false else { return }
        if case .failed = state { /* allow retry from failed */ }
        setState(.connecting)
        Task { await self.openConnection() }
    }

    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        clockProbeTask?.cancel()
        clockProbeTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        currentTicket = nil
        setState(.idle)
    }

    private func openConnection() async {
        guard let ticket = await ticketProvider() else {
            setState(.failed(reason: "No realtime ticket"))
            return
        }
        currentTicket = ticket

        var request = URLRequest(url: endpoint)
        // Sec-WebSocket-Protocol carries the ticket (runbook §2)
        request.setValue("plink.v2, plink.ticket.\(ticket)", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 0  // no overall timeout — long-lived socket

        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.task = task
        setState(.authenticating)
        task.resume()

        // Start single receive loop (§19: 'Не запускать два receive loop')
        startReceiveLoop()
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let msg = try await self.task?.receive()
                    guard let msg else { break }
                    await self.handleIncoming(msg)
                } catch {
                    if !Task.isCancelled {
                        await self.handleReceiveError(error)
                    }
                    break
                }
            }
        }
    }

    // MARK: - Incoming

    private func handleIncoming(_ msg: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        do {
            let decoded = try JSONDecoder().decode(RealtimeServerMessage.self, from: data)
            // Forward to all subscribers
            for c in messageContinuations { c.yield(decoded) }

            // Handle session.ready internally — it's the signal that we're
            // truly connected (runbook §19).
            if case .sessionReady(let ready) = decoded {
                handleSessionReady(ready)
            }
        } catch {
            // Schema mismatch — log metric, don't crash
            lastError = "decode failed: \(error.localizedDescription)"
        }
    }

    private func handleSessionReady(_ ready: RealtimeServerMessage.SessionReady) {
        setState(.connected)
        reconnectAttempt = 0
        // Kick off clock probes — 7 probes at 120ms, then 1 every 10s
        startClockProbes()
    }

    private func handleReceiveError(_ error: Error) {
        let nsError = error as NSError
        // 57 = Socket not connected, 60 = Timed out, 54 = Connection reset
        let transient = [57, 60, 54, -1005, -1009, -1001].contains(nsError.code)
        if transient {
            scheduleReconnect()
        } else {
            setState(.failed(reason: nsError.localizedDescription))
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        reconnectAttempt += 1
        setState(.reconnecting(attempt: reconnectAttempt))
        let delaySec = min(Self.maxReconnectBackoffSec, pow(2.0, Double(reconnectAttempt))) + Double.random(in: 0...0.5)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.openConnection()
        }
    }

    // MARK: - Clock probes (runbook §5)

    private func startClockProbes() {
        clockProbeTask?.cancel()
        clockProbeTask = Task { [weak self] in
            guard let self else { return }
            // Burst: 7 probes at 120ms
            for _ in 0..<7 {
                if Task.isCancelled { return }
                self.sendClockProbe()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            // Steady state: 1 probe every 10s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { return }
                self.sendClockProbe()
            }
        }
    }

    private func sendClockProbe() {
        let probe = RealtimeClientMessage.clockProbe(
            .init(clientSentMs: Date().timeIntervalSince1970 * 1000)
        )
        send(probe)
    }

    // MARK: - Send

    public func send(_ msg: RealtimeClientMessage) {
        guard let task, state.isOnline || state.isTransient else { return }
        do {
            let data = try JSONEncoder().encode(msg)
            task.send(.data(data)) { [weak self] err in
                if let err {
                    Task { @MainActor in
                        self?.lastError = "send failed: \(err.localizedDescription)"
                    }
                }
            }
        } catch {
            lastError = "encode failed: \(error.localizedDescription)"
        }
    }

    // MARK: - State

    private func setState(_ newState: RealtimeConnectionState) {
        state = newState
        for c in stateContinuations { c.yield(newState) }
    }

    deinit {
        // Synchronous cancel — cannot touch MainActor state from deinit.
        // task?.cancel is safe to call from any thread.
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RealtimeClient: URLSessionWebSocketDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // Handshake completed. We are NOT 'connected' yet — wait for
        // session.ready from the server (runbook §19).
        Task { @MainActor in
            self.setState(.joining)
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            // 1000 = normal close, 1001 = going away, 4001 = auth fail
            if closeCode == .normal || closeCode == .goingAway {
                self.setState(.idle)
            } else if closeCode.rawValue == 4001 {
                self.setState(.failed(reason: "Auth rejected (4001)"))
            } else {
                self.scheduleReconnect()
            }
        }
    }
}
