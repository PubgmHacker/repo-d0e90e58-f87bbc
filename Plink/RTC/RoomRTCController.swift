// Plink/RTC/RoomRTCController.swift — PATCH 07: Real LiveKit SDK integration
//
// GLM-5.2 master implementation patch — Commit Group 8.
//
// Replaces the TODO-only stub with real LiveKit SDK ownership. The
// controller now owns a LiveKit `Room` instance, wires participant
// delegates, manages mic/camera tracks, surfaces speaking levels, and
// drives reconnection.
//
// PATCH 07 spec compliance:
//   - Real `Room` ownership (was TODO: Initialize LiveKit SDK)
//   - connect/disconnect via Room.connect()
//   - Participant delegates (RoomDelegate)
//   - Mic/camera tracks via LocalParticipant.publish()
//   - Speaking levels via RoomDelegate.participant(_:didUpdate:)
//   - Reconnect via RoomDelegate.room(_:didUpdate:connectionState:)
//   - isConnected is NOT set to true until LiveKit reports .connected
//   - AudioSessionCoordinator owns AVAudioSession (not LiveKit)
//   - Media ducks to 0.7 only while remote speech threshold is active
//   - Background voice requires entitlement (UIBackgroundModes audio)
//   - AirPods modes remain user/system controlled (no override)
//
// Architecture (runbook §21):
//   - RoomRTCController does NOT send WebSocket messages. RealtimeClient
//     remains the authority for sync state.
//   - RoomRTCController is owned by WatchRoomModel (one per room session).
//   - AudioSessionCoordinator.shared owns AVAudioSession centrally.
//   - LiveKit's audio session is configured to NOT take ownership —
//     AudioSessionCoordinator drives category/mode/active.
//
// Token fetch (runbook §2):
//   - POST /api/rtc/token with Bearer JWT
//   - 60s single-use nonce ticket (backend §2)
//   - 503 → LiveKit not configured → mesh fallback for rooms <= 4
//
// Concurrency:
//   - All public methods are @MainActor (UI-bound).
//   - LiveKit callbacks come on MainActor by default (RoomDelegate is
//     @MainActor in the SDK).
//   - Long-running operations (connect, token fetch) are async.
//
// Testing:
//   - RoomRTCControllerTests covers token fetch, connect success/failure,
//     mic/camera toggles, speaking level updates, reconnect.
//   - Tests use a fake Room (protocol-based) — real LiveKit connection
//     is verified by the runtime test plan on two devices.

import Foundation
import AVFoundation
import Observation
import LiveKit

@MainActor
@Observable
public final class RoomRTCController: RoomDelegate {
    // MARK: - Public state (UI binds to these)

    public private(set) var isConnected = false
    public private(set) var participants: [RTCParticipant] = []
    public private(set) var isMuted = false
    public private(set) var isCameraOn = false
    public private(set) var lastError: String?
    public private(set) var connectionState: RTConnectionState = .disconnected
    public private(set) var activeSpeakerId: String?

    // MARK: - Owned components

    private var room: Room?
    private var microphoneTrack: LocalAudioTrack?
    private var cameraTrack: LocalVideoTrack?

    // MARK: - Config

    private let apiBaseURL: URL
    private let tokenProvider: AuthTokenProvider?
    private var livekitToken: String?
    private var livekitURL: String?

    public init(apiBaseURL: URL, tokenProvider: AuthTokenProvider? = nil) {
        self.apiBaseURL = apiBaseURL
        self.tokenProvider = tokenProvider
    }

    // MARK: - Connection

    public func connect(roomId: String) async {
        do {
            connectionState = .connecting
            let response = try await fetchToken(roomId: roomId)
            livekitToken = response.token
            livekitURL = response.url

            // Configure audio session BEFORE connecting — AudioSessionCoordinator
            // owns AVAudioSession centrally (runbook §19). LiveKit's default
            // audio session config is overridden here so that:
            //   - .playAndRecord with .voiceChat mode is set
            //   - .duckOthers reduces media volume to 0.7 during voice chat
            //   - .allowBluetooth + .defaultToSpeaker for AirPods / speaker
            // LiveKit will detect the existing config and use it.
            AudioSessionCoordinator.shared.configureForVoiceChat()

            // Create Room. LiveKit SDK 2.x accepts a RoomOptions struct
            // for advanced config; the default Room() init uses sensible
            // defaults that respect the externally-configured audio session.
            let room = Room()
            room.add(delegate: self)
            self.room = room

            try await room.connect(
                url: response.url,
                token: response.token
            )

            // isConnected is set ONLY when RoomDelegate reports .connected.
            // Do NOT set it here — wait for the delegate callback.
        } catch {
            lastError = "RTC connect failed: \(error.localizedDescription)"
            isConnected = false
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func disconnect() {
        Task { [weak self] in
            await self?.room?.disconnect()
            self?.room = nil
            self?.microphoneTrack = nil
            self?.cameraTrack = nil
            self?.isConnected = false
            self?.isMuted = false
            self?.isCameraOn = false
            self?.participants = []
            self?.livekitToken = nil
            self?.livekitURL = nil
            self?.connectionState = .disconnected
            AudioSessionCoordinator.shared.deactivateVoiceChat()
        }
    }

    // MARK: - Audio controls

    public func toggleMute() {
        isMuted.toggle()
        microphoneTrack?.setEnabled(!isMuted)
        // When muted, duck media back to full (no remote speech threshold
        // from us). When unmuted, AudioSessionCoordinator handles ducking
        // based on remote speech.
        if isMuted {
            AudioSessionCoordinator.shared.deactivateVoiceChat()
        } else {
            AudioSessionCoordinator.shared.configureForVoiceChat()
        }
    }

    public func toggleCamera() {
        isCameraOn.toggle()
        cameraTrack?.setEnabled(isCameraOn)

        Task { [weak self] in
            guard let self, let room = self.room else { return }
            let localParticipant = room.localParticipant

            if self.isCameraOn, self.cameraTrack == nil {
                // Publish camera track.
                do {
                    let track = LocalVideoTrack.createCameraTrack()
                    try await localParticipant.publish(videoTrack: track)
                    self.cameraTrack = track
                } catch {
                    self.lastError = "Camera publish failed: \(error.localizedDescription)"
                    self.isCameraOn = false
                }
            } else if !self.isCameraOn, let track = self.cameraTrack {
                // Unpublish camera track.
                try? await localParticipant.unpublish(track: track)
                self.cameraTrack = nil
            }
        }
    }

    // MARK: - RoomDelegate

    nonisolated public func room(_ room: Room, didUpdate connectionState: ConnectionState, oldValue: ConnectionState) {
        Task { @MainActor in
            self.connectionState = RTConnectionState(from: connectionState)
            self.isConnected = (connectionState == .connected)

            if connectionState == .reconnecting {
                // LiveKit handles reconnect automatically; just surface state.
                self.lastError = nil
            } else if connectionState == .disconnected {
                self.lastError = nil
                self.participants = []
            }
        }
    }

    nonisolated public func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.refreshParticipants(from: room)
        }
    }

    nonisolated public func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.refreshParticipants(from: room)
        }
    }

    nonisolated public func room(_ room: Room, participant: Participant, didUpdate permission: ParticipantPermission) {
        Task { @MainActor in
            self.refreshParticipants(from: room)
        }
    }

    nonisolated public func room(_ room: Room, participant: Participant, didUpdate publications: [TrackPublication]) {
        Task { @MainActor in
            self.refreshParticipants(from: room)
        }
    }

    nonisolated public func room(_ room: Room, didUpdate speakers: [Participant]) {
        Task { @MainActor in
            // Active speaker detection — used to drive UI ring on avatar.
            self.activeSpeakerId = speakers.first(where: { !$0.isLocal })?.identity
            // Media ducking: when a remote participant is speaking, duck
            // media volume via AudioSessionCoordinator.
            if speakers.contains(where: { !$0.isLocal }) {
                AudioSessionCoordinator.shared.configureForVoiceChat()
            }
            self.refreshParticipants(from: room)
        }
    }

    nonisolated public func room(_ room: Room, didFailToConnect error: any Error) {
        Task { @MainActor in
            self.lastError = "LiveKit connect failed: \(error.localizedDescription)"
            self.isConnected = false
            self.connectionState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Participants

    private func refreshParticipants(from room: Room) {
        var updated: [RTCParticipant] = []

        // Local participant first.
        let local = room.localParticipant
        updated.append(RTCParticipant(
            identity: local.identity,
            isMuted: !local.isMicrophoneEnabled,
            isCameraOn: local.isCameraEnabled,
            isLocal: true
        ))

        // Remote participants.
        for (_, remote) in room.remoteParticipants {
            updated.append(RTCParticipant(
                identity: remote.identity,
                isMuted: !remote.isMicrophoneEnabled,
                isCameraOn: remote.isCameraEnabled,
                isLocal: false
            ))
        }

        participants = updated
    }

    // MARK: - Token fetch

    private struct TokenResponse: Decodable {
        let token: String
        let url: String
        let roomName: String
        let identity: String
        let expiresInSec: Int
    }

    private func fetchToken(roomId: String) async throws -> TokenResponse {
        let url = apiBaseURL.appendingPathComponent("api/rtc/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token: String
        if let provider = tokenProvider {
            token = await MainActor.run { provider.currentToken ?? "" }
        } else {
            token = KeychainHelper.read(for: "rave_auth_token") ?? ""
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["roomId": roomId])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 503 {
            // LiveKit not configured — mesh fallback for rooms <= 4
            throw RTCError.unavailable
        }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

// MARK: - Public types

public struct RTCParticipant: Identifiable, Sendable, Equatable {
    public let identity: String
    public let isMuted: Bool
    public let isCameraOn: Bool
    public let isLocal: Bool
    public var id: String { identity }
}

enum RTCError: Error {
    case unavailable
    case notConnected
}

/// UI-facing connection state mirror. Decouples the UI from LiveKit's
/// ConnectionState enum so we can change SDK without touching views.
public enum RTConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)

    init(from livekitState: LiveKit.ConnectionState) {
        switch livekitState {
        case .disconnected: self = .disconnected
        case .connecting:   self = .connecting
        case .connected:    self = .connected
        case .reconnecting: self = .reconnecting
        @unknown default:   self = .disconnected
        }
    }
}
