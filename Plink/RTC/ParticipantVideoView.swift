// Plink/RTC/ParticipantVideoView.swift — PATCH 09: LiveKit video rendering
//
// GLM-5.2 master implementation patch — Commit Group 9.
//
// SwiftUI wrapper around LiveKit's VideoView. Renders a participant's
// camera track (local or remote) inside a circular avatar that replaces
// the letter-based avatar when the participant has video enabled.
//
// Usage:
//   ParticipantVideoView(track: controller.videoTrack(forParticipantIdentity: id))
//     .frame(width: 36, height: 36)
//     .clipShape(Circle())
//
// Design:
//   - Mirrored layout for local participant (selfie convention).
//   - .scaleAspectFill by default — fills the circle, may crop.
//   - Smooth transition when track appears/disappears (opacity fade).
//   - Falls back to letter avatar when track is nil.
//
// Architecture:
//   - ParticipantVideoView is a UIViewRepresentable wrapping LiveKit's
//     VideoView (UIKit-based for performance).
//   - The VideoView is reusable — updateUIView rebinds the track without
//     recreating the underlying view.
//   - Layout parameters (mirror, aspect fill) are set once in makeUIView.
//
// Performance:
//   - VideoView uses Metal for rendering — sub-millisecond frame updates.
//   - One VideoView per visible participant (max 5 in PresenceBar).
//   - When a participant leaves, dismantleUIView stops the track render.
//
// Testing:
//   - Runtime test plan: publish local camera, verify self-preview shows;
//     remote participant publishes, verify their avatar shows video.

import SwiftUI
import LiveKit

/// SwiftUI wrapper for LiveKit's VideoView. Renders a participant's
/// camera track inside a circular avatar.
struct ParticipantVideoView: UIViewRepresentable {
    let track: VideoTrack?
    let isMirrored: Bool

    init(track: VideoTrack?, isMirrored: Bool = false) {
        self.track = track
        self.isMirrored = isMirrored
    }

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.mirrorMode = isMirrored ? .mirror : .off
        view.contentMode = .scaleAspectFill
        view.backgroundColor = UIColor(PlinkRave.raised)
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        // Rebind track — VideoView handles attach/detach internally.
        if uiView.track !== track {
            uiView.track = track
        }
    }

    static func dismantleUIView(_ uiView: VideoView, coordinator: ()) {
        // Detach track to stop rendering when view is removed.
        uiView.track = nil
    }
}

/// Composite view that shows video when track is available, falls back
/// to letter avatar otherwise. Used in PresenceBar.
struct ParticipantAvatarWithVideo: View {
    let participant: RTCParticipant
    let hostId: String?
    let isSpeaking: Bool
    let videoTrack: VideoTrack?

    private var isHost: Bool { participant.identity == hostId }
    private var hasVideo: Bool { videoTrack != nil }

    var body: some View {
        ZStack {
            if let track = videoTrack {
                ParticipantVideoView(
                    track: track,
                    isMirrored: participant.isLocal
                )
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(ringColor, lineWidth: 1.5)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                // Letter avatar fallback
                Circle()
                    .fill(PlinkRave.raised)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(participant.identity.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PlinkRave.text)
                    )
                    .overlay(
                        Circle()
                            .stroke(ringColor, lineWidth: 1.5)
                    )
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Host crown badge — always shown regardless of video state
            if isHost {
                Image(systemName: "crown.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(PlinkRave.gold)
                    .background(PlinkRave.void, in: Circle())
                    .frame(width: 14, height: 14)
                    .offset(x: 1, y: 1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: hasVideo)
    }

    private var ringColor: Color {
        if isSpeaking { return PlinkRave.success }
        if isHost { return PlinkRave.gold.opacity(0.6) }
        return PlinkRave.success.opacity(0.18)
    }
}
