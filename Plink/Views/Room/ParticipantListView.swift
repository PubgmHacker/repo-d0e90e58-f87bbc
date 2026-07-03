import SwiftUI

// MARK: - Participant List View
struct ParticipantListView: View {
    let room: Room

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Text("Participants")
                            .font(.headline)
                            .foregroundColor(.raveTextPrimary)

                        Spacer()

                        Text("\(room.participantCount)/\(room.maxParticipants)")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundColor(.ravePrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.raveCard)
                            .clipShape(Capsule())
                    }

                    // Room code share
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Room Code")
                                .font(.caption)
                                .foregroundColor(.raveTextSecondary)
                            Text(room.code)
                                .font(.title2.bold().monospaced())
                                .foregroundColor(.ravePrimary)
                        }

                        Spacer()

                        Button {
                            UIPasteboard.general.string = room.code
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.ravePrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.ravePrimary.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(14)
                    .background(Color.raveCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Divider()
                        .background(Color.raveSurface)

                    // Participant list
                    Text("In Room")
                        .font(.caption.bold())
                        .foregroundColor(.raveTextSecondary)

                    LazyVStack(spacing: 10) {
                        // Host first
                        if let host = room.participants.first(where: { $0.id == room.hostID }) {
                            ParticipantRow(user: host, isHost: true)
                        }

                        // Other participants
                        ForEach(room.participants.filter { $0.id != room.hostID }) { user in
                            ParticipantRow(user: user, isHost: false)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Participant Row
private struct ParticipantRow: View {
    let user: UserPreview
    let isHost: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.ravePrimary)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(user.username.prefix(1).uppercased())
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                    )

                // Online indicator
                Circle()
                    .fill(user.isOnline ? Color.raveGreen : Color.raveTextSecondary.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.raveBackground, lineWidth: 2)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.username)
                        .font(.subheadline.bold())
                        .foregroundColor(.raveTextPrimary)

                    if isHost {
                        Text("HOST")
                            .font(.caption2.bold())
                            .foregroundColor(.raveWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.raveWarning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text(user.isOnline ? "Online" : "Offline")
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.raveCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
