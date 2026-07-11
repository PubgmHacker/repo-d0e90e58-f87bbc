import SwiftUI

struct PresenceBar: View {
    let model: WatchRoomModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -6) {
                ForEach(model.participants.prefix(5)) { participant in
                    ParticipantAvatar(participant: participant, hostId: model.hostId)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.participants.count) in room")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PlinkRave.text)
                Text(model.activeSpeakerName.map { "\($0) speaking" } ?? "Watching together")
                    .font(.system(size: 10))
                    .foregroundStyle(PlinkRave.textTertiary)
            }

            Spacer()

            VoiceActionButton(state: model.microphoneState) { Task { await model.toggleMicrophone() } }
            CameraActionButton(state: model.cameraState) { Task { await model.toggleCamera() } }
        }
        .padding(.horizontal, 12)
        .background(PlinkRave.void)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PlinkRave.divider.opacity(0.3)).frame(height: 0.5)
        }
    }
}
