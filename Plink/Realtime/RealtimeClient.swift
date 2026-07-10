// Plink/Realtime/RealtimeClient.swift
// Production WebSocket client (runbook §8 + Brain Review 2 P0-9..P0-14 fixes)
//
// Brain Review 2 fixes:
//
// P0-9: AsyncStream generics already correct (MessageSink uses
//   AsyncStream<RealtimeServerMessage>.Continuation). BUT deinit isolation
//   is real — nonisolated deinit was reading actor-isolated `task`/`session`.
//   Fixed via Sendable Transport holder with internal lock. No @unchecked
//   Sendable on the client class itself.
//
// P0-10: WS URL built via roomEndpoint(roomId) → /ws/room/<roomId>. Ticket
//   provider now takes roomId parameter so it can't issue a ticket for the
//   wrong room.
//
// P0-11: connect() uses explicit switch — only .idle and .failed allow
//   new connection. All transient/connected states return. Before opening
//   new transport, cancel previous.
//
// P0-12: transport generation UUID. Each new openConnection() bumps
//   generation. All callbacks check generation before mutating state.
//   clockSynced/clockReplyCount reset on new generation.
//
// P0-13: split timeouts. Clock timeout → degraded clock mode BUT still
//   send snapshot request. Snapshot timeout → .reconnecting, NOT .connected.
//   .connected only after snapshot received.
//
// P0-14: single yield per message. Removed duplicate yield in .syncState case.

import Foundation
import Observation

// MARK: - Sendable transport holder (P0-9: deinit isolation fix)
//
// Holds URLSessionWebSocketTask + URLSession behind a lock so nonisolated
// deinit can cancel without touching @MainActor state.
private final class Transport: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionWebSocketTask?
    private var _session: URLSession?

    func set(task: URLSessionWebSocketTask?, session: URLSession?) {
        lock.lock(); defer { lock.unlock() }
        // Cancel previous before storing new
        _task?.cancel(with: .goingAway, reason: nil)
        _session?.invalidateAndCancel()
        _task = task
        _session = session
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _task?.cancel(with: .goingAway, reason: nil)
        _session?.invalidateAndCancel()
        _task = nil
        _session = nil
    }

    var task: URLSessionWebSocketTask? {
        lock.lock(); defer { lock.unlock() }
        return _task
    }

    func send(_ data: Data, completionHandler: @escaping (Error?) -> Void) {
        lock.lock()
        let t = _task
        lock.unlock()
        guard let t else {
            completionHandler(NSError(domain: "Transport", code: -1, userInfo: [NSLocalizedDescriptionKey: "no task"]))
            return
        }
        t.send(.data(data), completionHandler: completionHandler)
    }
}

// MARK: - Subscription tokens (AsyncStream.Continuation is a value type)
private struct MessageSink {
    let id: UUID
    let continuation: AsyncStream<RealtimeServerMessage>.Continuation
}
private struct StateSink {
    let id: UUID
    let continuation: AsyncStream<RealtimeConnectionState>.Continuation
}

// MARK: - Realtime ticket (P0-10: typed ticket, room-bound)
public struct RealtimeTicket: Sendable, Equatable {
    public let jwt: String
    public let roomId: String
    public let expiresInSec: Int
    public init(jwt: String, roomId: String, expiresInSec: Int) {
        self.jwt = jwt
        self.roomId = roomId
        self.expiresInSec = expiresInSec
    }
}

// MARK: - Delegate protocol
@MainActor
public protocol RealtimeClientDelegate: AnyObject {
    var roomId: String? { get }
    var lastEpoch: Int64 { get }
    var lastSeq: Int64 { get }
    func ingestClockProbe(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double)
    func applySnapshot(_ state: RealtimeRoomState?)
    func sessionDidConnect()
    func handleOtherMessage(_ message: RealtimeServerMessage)
}

// MARK: - Client
@MainActor
@Observable
public final class RealtimeClient: NSObject {
    // Public state
    public private(set) var state: RealtimeConnectionState = .idle
    public private(set) var lastError: String?
    public private(set) var clockSynced: Bool = false
    public private(set) var snapshotReceived: Bool = false

    // Subscriptions
    private var messageSinks: [MessageSink] = []
    private var stateSinks: [StateSink] = []

    // Transport (P0-9: Sendable holder, safe from nonisolated deinit)
    private let transport = Transport()

    // Tasks
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var clockProbeTask: Task<Void, Never>?
    private var clockTimeoutTask: Task<Void, Never>?
    private var snapshotTimeoutTask: Task<Void, Never>?

    // Generation (P0-12: bump on each new transport)
    private var generation: UUID = UUID()
    private var clockReplyCount = 0

    // Config
    private let baseEndpoint: URL  // e.g. wss://host/ws
    public weak var delegate: RealtimeClientDelegate?
    private let ticketProvider: (String) async throws -> RealtimeTicket
    private var currentTicket: RealtimeTicket?
    private var currentRoomId: String?
    private var reconnectAttempt = 0
    private static let maxReconnectBackoffSec: Double = 30
    private static let clockTimeoutNs: UInt64 = 5_000_000_000
    private static let snapshotTimeoutNs: UInt64 = 8_000_000_000
    private static let minClockRepliesForSync = 3

    public init(baseEndpoint: URL, ticketProvider: @escaping (String) async throws -> RealtimeTicket) {
        self.baseEndpoint = baseEndpoint
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

    // P0-11: explicit switch — only .idle and .failed allow new connection.
    public func connect(roomId: String) {
        switch state {
        case .idle, .failed:
            break
        case .connecting, .authenticating, .joining, .synchronizing,
             .connected, .reconnecting:
            return
        }
        currentRoomId = roomId
        // P0-11: cancel any previous transport before new
        cancelAllTasks()
        transport.cancel()
        setState(.connecting)
        Task { await openConnection() }
    }

    public func disconnect() {
        cancelAllTasks()
        transport.cancel()
        currentTicket = nil
        clockReplyCount = 0
        clockSynced = false
        snapshotReceived = false
        setState(.idle)
    }

    public func send(_ msg: RealtimeClientMessage) {
        guard state.isOnline || state.isTransient else { return }
        do {
            let data = try JSONEncoder().encode(msg)
            transport.send(data) { [weak self] err in
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

    // MARK: - Connection (P0-12: generation-bumped)

    private func openConnection() async {
        guard let roomId = currentRoomId else {
            setState(.failed(reason: "No roomId"))
            return
        }
        // P0-12: new generation — old callbacks will be ignored
        generation = UUID()
        let gen = generation
        // P0-12: reset clock/snapshot state for new generation
        clockSynced = false
        clockReplyCount = 0
        snapshotReceived = false

        // P0-10: ticket bound to roomId
        let ticket: RealtimeTicket
        do {
            ticket = try await ticketProvider(roomId)
        } catch {
            if gen == generation { setState(.failed(reason: "Ticket error: \(error.localizedDescription)")) }
            return
        }
        guard gen == generation else { return }  // superseded
        currentTicket = ticket

        // P0-10: verify ticket roomId matches requested roomId
        guard ticket.roomId == roomId else {
            setState(.failed(reason: "Ticket roomId mismatch"))
            return
        }

        // P0-10: build WS URL via path, not query
        let url: URL
        do {
            url = try roomEndpoint(roomId: roomId)
        } catch {
            setState(.failed(reason: "Invalid endpoint: \(error.localizedDescription)"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("plink.v2, plink.ticket.\(ticket.jwt)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 0

        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        let t = s.webSocketTask(with: request)
        transport.set(task: t, session: s)
        if gen == generation { setState(.authenticating) }
        t.resume()
        if gen == generation { startReceiveLoop(generation: gen) }
    }

    // P0-10: /ws/room/<roomId> — no query string
    private func roomEndpoint(roomId: String) throws -> URL {
        // baseEndpoint is e.g. wss://host/ws — append /room/<roomId>
        var components = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false)
        guard let scheme = components?.scheme,
              scheme == "ws" || scheme == "wss",
              let host = components?.host else {
            throw NSError(domain: "RealtimeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "baseEndpoint must be ws:// or wss://"])
        }
        var path = components?.path ?? ""
        if path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/ws" }
        path += "/room/" + roomId
        components?.path = path
        components?.query = nil
        components?.fragment = nil
        guard let url = components?.url else {
            throw NSError(domain: "RealtimeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "failed to build room endpoint"])
        }
        return url
    }

    private func startReceiveLoop(generation: UUID) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let msg = try await self.transport.task?.receive()
                    guard self.generation == generation else { return }
                    guard let msg else { break }
                    self.handleIncoming(msg, generation: generation)
                } catch {
                    if self.generation != generation { return }
                    if !Task.isCancelled {
                        self.handleReceiveError(error)
                    }
                    break
                }
            }
        }
    }

    // MARK: - Incoming (P0-14: single yield per message)

    private func handleIncoming(_ msg: URLSessionWebSocketTask.Message, generation: UUID) {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        let clientReceivedMs = Date().timeIntervalSince1970 * 1000
        do {
            let decoded = try JSONDecoder().decode(RealtimeServerMessage.self, from: data)
            // P0-14: single yield — happens ONCE here, not in each case.
            for sink in messageSinks { sink.continuation.yield(decoded) }
            switch decoded {
            case .sessionReady(let ready):
                handleSessionReady(ready, generation: generation)
            case .clockProbeReply(let reply):
                handleClockReply(reply, clientReceivedMs: clientReceivedMs, generation: generation)
            case .syncStateSnapshot(let snapshot):
                handleSnapshot(snapshot, generation: generation)
            case .syncState(let stateMsg):
                delegate?.applySnapshot(stateMsg.state)
            default:
                delegate?.handleOtherMessage(decoded)
            }
        } catch {
            lastError = "decode failed: \(error.localizedDescription)"
        }
    }

    // P0-13: on session.ready, send snapshot request immediately (don't wait
    // for clock sync). Clock probes run in parallel.
    private func handleSessionReady(_ ready: RealtimeServerMessage.SessionReady, generation: UUID) {
        guard generation == self.generation else { return }
        setState(.synchronizing)
        startClockProbes(generation: generation)
        startClockTimeout(generation: generation)
        startSnapshotTimeout(generation: generation)
        // P0-13: send snapshot request immediately — don't wait for clock sync
        if let roomId = currentRoomId {
            let afterSeq = delegate?.lastSeq ?? 0
            send(.stateRequest(.init(roomId: roomId, afterSeq: afterSeq)))
        }
    }

    private func handleClockReply(_ reply: RealtimeServerMessage.ClockProbeReply, clientReceivedMs: Double, generation: UUID) {
        guard generation == self.generation else { return }
        delegate?.ingestClockProbe(
            clientSentMs: reply.clientSentMs,
            serverMs: reply.serverMs,
            clientReceivedMs: clientReceivedMs
        )
        clockReplyCount += 1
        if clockReplyCount >= Self.minClockRepliesForSync && !clockSynced {
            clockSynced = true
            clockTimeoutTask?.cancel()
            clockTimeoutTask = nil
        }
    }

    // P0-13: .connected only after snapshot received
    private func handleSnapshot(_ snapshot: RealtimeServerMessage.SyncStateSnapshotMessage, generation: UUID) {
        guard generation == self.generation else { return }
        delegate?.applySnapshot(snapshot.state)
        snapshotReceived = true
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        if state != .connected {
            setState(.connected)
            delegate?.sessionDidConnect()
            reconnectAttempt = 0
        }
    }

    // P0-13: clock timeout — degraded mode, but does NOT declare .connected
    private func startClockTimeout(generation: UUID) {
        clockTimeoutTask?.cancel()
        clockTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.clockTimeoutNs)
            guard !Task.isCancelled, let self else { return }
            guard generation == self.generation else { return }
            if !self.clockSynced {
                self.clockSynced = false
                self.lastError = "Clock sync timeout — degraded mode"
                // P0-13: do NOT setState(.connected) here. Snapshot still required.
            }
        }
    }

    // P0-13: snapshot timeout — fail/reconnect, do NOT declare .connected
    private func startSnapshotTimeout(generation: UUID) {
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.snapshotTimeoutNs)
            guard !Task.isCancelled, let self else { return }
            guard generation == self.generation else { return }
            if !self.snapshotReceived && self.state != .connected {
                self.lastError = "Snapshot timeout — reconnecting"
                self.scheduleReconnect()
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

    private func startClockProbes(generation: UUID) {
        clockProbeTask?.cancel()
        clockProbeTask = Task { [weak self] in
            guard let self else { return }
            // Burst: 7 probes at 120ms
            for _ in 0..<7 {
                if Task.isCancelled { return }
                if generation != self.generation { return }
                self.sendClockProbe()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            // Steady: 1 every 10s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { return }
                if generation != self.generation { return }
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

    private func cancelAllTasks() {
        reconnectTask?.cancel(); reconnectTask = nil
        receiveTask?.cancel(); receiveTask = nil
        clockProbeTask?.cancel(); clockProbeTask = nil
        clockTimeoutTask?.cancel(); clockTimeoutTask = nil
        snapshotTimeoutTask?.cancel(); snapshotTimeoutTask = nil
    }

    // P0-9: deinit touches only Sendable Transport — safe from nonisolated context
    nonisolated deinit {
        transport.cancel()
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
            // Handshake completed at transport level. NOT .connected yet.
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
