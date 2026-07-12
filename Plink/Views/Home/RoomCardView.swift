// Plink/Views/Home/RoomCardView.swift — GPT-5.6 V4 §6
// Clean card surface, no negative offsets or nested glass.

import SwiftUI

struct RoomCardView: View {
    let room: Room
    var onReport: ((Room) -> Void)?
    var onBlock: ((Room) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Artwork
            ZStack(alignment: .topLeading) {
                AsyncImage(url: URL(string: room.mediaItem?.thumbnailURL ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if room.isActive {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Cinema2026.danger, in: Capsule())
                        .foregroundStyle(.white).padding(6)
                }
            }

            Text(room.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
                .lineLimit(1)

            HStack {
                Label("\(room.participantCount)", systemImage: "person.2.fill")
                Spacer()
                Text(room.mediaItem?.title ?? "Без видео")
            }
            .font(.system(size: 12))
            .foregroundStyle(Cinema2026.secondary)
        }
        .padding(14)
        .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("\(room.name), \(room.participantCount) участников")
    }
}
