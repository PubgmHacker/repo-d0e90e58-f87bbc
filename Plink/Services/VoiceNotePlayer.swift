// Plink/Services/VoiceNotePlayer.swift
// Plays friend-DM voice notes via authenticated download + AVAudioPlayer.

import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceNotePlayer: NSObject {
    static let shared = VoiceNotePlayer()

    private(set) var playingMessageId: String?
    private(set) var progress: Double = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var tickTimer: Timer?
    private var cache: [String: URL] = [:]
    private let api = APIClient.shared

    func toggle(messageId: String) {
        if playingMessageId == messageId {
            stop()
            return
        }
        Task { await play(messageId: messageId) }
    }

    func play(messageId: String) async {
        stop(keepCache: true)
        errorMessage = nil
        isLoading = true
        playingMessageId = messageId
        defer { isLoading = false }

        do {
            let fileURL = try await localFile(for: messageId)
            try configurePlaybackSession()
            let p = try AVAudioPlayer(contentsOf: fileURL)
            p.delegate = self
            p.prepareToPlay()
            guard p.play() else {
                throw URLError(.cannotDecodeContentData)
            }
            player = p
            progress = 0
            startTick()
        } catch {
            errorMessage = error.localizedDescription
            playingMessageId = nil
            print("[VoiceNote] play error: \(error)")
        }
    }

    func stop(keepCache: Bool = true) {
        tickTimer?.invalidate()
        tickTimer = nil
        player?.stop()
        player = nil
        playingMessageId = nil
        progress = 0
        if !keepCache {
            for (_, url) in cache {
                try? FileManager.default.removeItem(at: url)
            }
            cache.removeAll()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Download

    private func localFile(for messageId: String) async throws -> URL {
        if let cached = cache[messageId], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        // Ensure auth token
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
        guard let token = api.authToken else {
            throw URLError(.userAuthenticationRequired)
        }

        let base = api.baseURL
        let url = base.appendingPathComponent("messages/voice/\(messageId)")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .returnCacheDataElseLoad

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard data.count > 100 else {
            throw URLError(.zeroByteResource)
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("plink-voice-play", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(messageId).m4a")
        try data.write(to: file, options: .atomic)
        cache[messageId] = file
        return file
    }

    private func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    private func startTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = min(1, p.currentTime / p.duration)
            }
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
    }
}

extension VoiceNotePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.progress = 1
            self.playingMessageId = nil
            self.tickTimer?.invalidate()
            self.tickTimer = nil
            self.player = nil
        }
    }
}
