import SwiftUI

struct PresenceBar: View {
    let model: WatchRoomModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(model.participants.prefix(4)) { participant in
                    ParticipantAvatar(participant: participant, hostId: model.hostId)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.participants.count) in the room")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlinkRave.text)
                Text(model.activeSpeakerName.map { "\($0) is speaking" } ?? "Watching together")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PlinkRave.textSecondary)
            }

            Spacer()

            VoiceActionButton(state: model.microphoneState) { Task { await model.toggleMicrophone() } }
            CameraActionButton(state: model.cameraState) { Task { await model.toggleCamera() } }
        }
        .padding(.horizontal, 14)
        .background(PlinkRave.void)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PlinkRave.divider.opacity(0.45)).frame(height: 1)
        }
    }
}
