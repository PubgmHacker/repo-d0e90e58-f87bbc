// Plink/Realtime/RealtimeClient.swift
// Production WebSocket client (runbook §8 + Brain Review P0-4, P0-5 fixes)
//
// Brain Review P0-4 fix: complete handshake protocol.
//   WS open → .joining → session.ready → .synchronizing →
//   ingest ≥3 clock replies → send sync.state.request(roomId, afterSeq) →
//   receive snapshot → hand to OrderedSyncController → .connected
//   Timeout 5s for clock sync — degraded mode, not infinite wait.
//
// Brain Review P0-5 fix: compile correctness.
//   - Use @MainActor @Observable (type macro on the class), NOT @Observable
//     on stored properties inside ObservableObject.
//   - AsyncStream.Continuation is a value type — comparison by === is
//     illegal. Use UUID tokens to identify subscriptions for removal.
//   - URLSessionWebSocketDelegate methods are nonisolated and hop to
//     MainActor for state mutation.
//   - deinit performs only synchronous, non-isolated cleanup (socket.cancel,
//     session.invalidateAndCancel) — does NOT touch @MainActor state.

import Foundation
import Observation

// MARK: - Subscription tokens (P0-5: AsyncStream.Continuation is a value type,
// cannot be compared by ===. Use UUID for identity.)
private struct MessageSink {
    let id: UUID
    let continuation: AsyncStream<RealtimeServerMessage>.Continuation
}
private struct StateSink {
    let id: UUID
    let continuation: AsyncStream<RealtimeConnectionState>.Continuation
}

/// Orchestration interface — RealtimeClient needs to know roomId, last
/// (epoch, seq) watermark, and where to hand clock replies + snapshots.
/// The concrete owner is WatchRoomModel (Stage 10). For now we expose a
/// protocol so the client is testable in isolation.
@MainActor
public protocol RealtimeClientDelegate: AnyObject {
    /// The room this session is bound to.
    var roomId: String? { get }

    /// Last applied (epoch, seq) watermark — used as afterSeq in snapshot
    /// request after reconnect.
    var lastEpoch: Int64 { get }
    var lastSeq: Int64 { get }

    /// Called for each clock.probe.reply. Must call clockSynchronizer.ingest.
    func ingestClockProbe(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double)

    /// Called when sync.state.snapshot arrives — typically hands to
    /// OrderedSyncController.apply().
    func applySnapshot(_ state: RealtimeRoomState?)

    /// Called when session is fully established (clock synced + snapshot
    /// received). Delegate may flip its UI to 'connected'.
    func sessionDidConnect()

    /// Called when any other server message arrives (chat, reaction,
    /// participant events, errors). Delegate routes to appropriate consumer.
    func handleOtherMessage(_ message: RealtimeServerMessage)
}

@MainActor
@Observable
public final class RealtimeClient: NSObject {
    // MARK: - Public state (P0-5: @Observable on the class, no per-property annotation)
    public private(set) var state: RealtimeConnectionState = .idle
    public private(set) var lastError: String?
    public private(set) var clockSynced: Bool = false

    // MARK: - Subscriptions
    private var messageSinks: [MessageSink] = []
    private var stateSinks: [StateSink] = []

    // MARK: - Networking
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var clockProbeTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var clockReplyCount = 0

    // MARK: - Config
    private let endpoint: URL
    public weak var delegate: RealtimeClientDelegate?
    private let ticketProvider: () async -> String?
    private var currentTicket: String?
    private var currentRoomId: String?
    private var reconnectAttempt = 0
    private static let maxReconnectBackoffSec: Double = 30
    private static let clockSyncTimeoutNs: UInt64 = 5_000_000_000
    private static let minClockRepliesForSync = 3

    public init(endpoint: URL, ticketProvider: @escaping () async -> String?) {
        self.endpoint = endpoint
        self.ticketProvider = ticketProvider
        super.init()
    }

    // MARK: - Public API

    public var messages: AsyncStream<RealtimeServerMessage> {
        AsyncStream { continuation in
            let sink = MessageSink(id: UUID(), continuation: continuation)
            self.messageSinks.append(sink)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.messageSinks.removeAll { $0.id == sink.id }
                }
            }
        }
    }

    public var stateChanges: AsyncStream<RealtimeConnectionState> {
        AsyncStream { continuation in
            let sink = StateSink(id: UUID(), continuation: continuation)
            self.stateSinks.append(sink)
            continuation.yield(self.state)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stateSinks.removeAll { $0.id == sink.id }
                }
            }
        }
    }

    public func connect(roomId: String) {
        currentRoomId = roomId
        guard state == .idle || !state.isTransient || state.isOnline == false else { return }
        if case .failed = state { /* allow retry */ }
        setState(.connecting)
        Task { await openConnection() }
    }

    public func disconnect() {
        reconnectTask?.cancel(); reconnectTask = nil
        receiveTask?.cancel(); receiveTask = nil
        clockProbeTask?.cancel(); clockProbeTask = nil
        handshakeTimeoutTask?.cancel(); handshakeTimeoutTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        currentTicket = nil
        clockReplyCount = 0
        clockSynced = false
        setState(.idle)
    }

    public func send(_ msg: RealtimeClientMessage) {
        guard let task, state.isOnline || state.isTransient else { return }
        do {
            let data = try JSONEncoder().encode(msg)
            task.send(.data(data)) { [weak self] err in
                if let err {
                    Task { @MainActor [weak self] in
                        self?.lastError = "send failed: \(err.localizedDescription)"
                    }
                }
            }
        } catch {
            lastError = "encode failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Connection

    private func openConnection() async {
        guard let roomId = currentRoomId else {
            setState(.failed(reason: "No roomId"))
            return
        }
        guard let ticket = await ticketProvider() else {
            setState(.failed(reason: "No realtime ticket"))
            return
        }
        currentTicket = ticket

        var request = URLRequest(url: endpoint)
        request.setValue("plink.v2, plink.ticket.\(ticket)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 0

        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = s
        let t = s.webSocketTask(with: request)
        self.task = t
        setState(.authenticating)
        t.resume()
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
                    self.handleIncoming(msg)
                } catch {
                    if !Task.isCancelled {
                        self.handleReceiveError(error)
                    }
                    break
                }
            }
        }
    }

    // MARK: - Incoming

    private func handleIncoming(_ msg: URLSessionWebSocketTask.Message) {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        let clientReceivedMs = Date().timeIntervalSince1970 * 1000
        do {
            let decoded = try JSONDecoder().decode(RealtimeServerMessage.self, from: data)
            for sink in messageSinks { sink.continuation.yield(decoded) }
            switch decoded {
            case .sessionReady(let ready):
                handleSessionReady(ready)
            case .clockProbeReply(let reply):
                handleClockReply(reply, clientReceivedMs: clientReceivedMs)
            case .syncStateSnapshot(let snapshot):
                handleSnapshot(snapshot)
            case .syncState(let stateMsg):
                // Live authoritative update — delegate applies it.
                delegate?.applySnapshot(stateMsg.state)
                for sink in messageSinks { sink.continuation.yield(decoded) }
            default:
                delegate?.handleOtherMessage(decoded)
            }
        } catch {
            lastError = "decode failed: \(error.localizedDescription)"
        }
    }

    // P0-4: complete handshake on session.ready
    private func handleSessionReady(_ ready: RealtimeServerMessage.SessionReady) {
        setState(.synchronizing)
        // Start clock probes immediately — we need ≥3 replies before .connected
        startClockProbes()
        // Start handshake timeout — if clock sync doesn't converge in 5s,
        // proceed in degraded mode (clockSynced=false) so UI doesn't hang.
        startHandshakeTimeout()
    }

    private func handleClockReply(_ reply: RealtimeServerMessage.ClockProbeReply, clientReceivedMs: Double) {
        delegate?.ingestClockProbe(
            clientSentMs: reply.clientSentMs,
            serverMs: reply.serverMs,
            clientReceivedMs: clientReceivedMs
        )
        clockReplyCount += 1
        if clockReplyCount >= Self.minClockRepliesForSync && !clockSynced {
            clockSynced = true
            // Send snapshot request — afterSeq = last applied watermark
            guard let roomId = currentRoomId else { return }
            let afterSeq = delegate?.lastSeq ?? 0
            send(.stateRequest(.init(roomId: roomId, afterSeq: afterSeq)))
        }
    }

    private func handleSnapshot(_ snapshot: RealtimeServerMessage.SyncStateSnapshotMessage) {
        // Hand snapshot to OrderedSyncController (via delegate)
        delegate?.applySnapshot(snapshot.state)
        // P1-8: if snapshot (epoch, seq) is not newer than watermark, treat
        // as reconciliation ack — still proceed to .connected.
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        if state != .connected {
            setState(.connected)
            delegate?.sessionDidConnect()
            reconnectAttempt = 0
        }
    }

    private func startHandshakeTimeout() {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.clockSyncTimeoutNs)
            guard !Task.isCancelled, let self else { return }
            // Timeout — proceed in degraded mode
            if self.state != .connected {
                self.clockSynced = false
                self.lastError = "Clock sync timeout — proceeding in degraded mode"
                self.setState(.connected)
                self.delegate?.sessionDidConnect()
            }
        }
    }

    private func handleReceiveError(_ error: Error) {
        let nsError = error as NSError
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

    // MARK: - Clock probes

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
            // Steady: 1 every 10s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { return }
                self.sendClockProbe()
            }
        }
    }

    private func sendClockProbe() {
        send(.clockProbe(.init(clientSentMs: Date().timeIntervalSince1970 * 1000)))
    }

    private func setState(_ newState: RealtimeConnectionState) {
        state = newState
        for sink in stateSinks { sink.continuation.yield(newState) }
    }

    // P0-5: deinit must NOT touch @MainActor state. Only synchronous
    // non-isolated socket/session cancellation.
    nonisolated deinit {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }
}

// MARK: - URLSessionWebSocketDelegate (nonisolated, hop to MainActor)

extension RealtimeClient: URLSessionWebSocketDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            // Handshake completed at transport level. NOT .connected yet —
            // wait for session.ready + clock sync + snapshot.
            self?.setState(.joining)
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if closeCode == .normal || closeCode == .goingAway {
                self.setState(.idle)
            } else if closeCode.rawValue == 4001 {
                self.setState(.failed(reason: "Auth rejected (4001)"))
            } else if closeCode.rawValue == 4003 {
                self.setState(.failed(reason: "Forbidden (4003) — not member/host"))
            } else {
                self.scheduleReconnect()
            }
        }
    }
}
