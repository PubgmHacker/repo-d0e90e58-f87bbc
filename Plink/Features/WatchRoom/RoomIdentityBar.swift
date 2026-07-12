// Plink/Features/WatchRoom/RoomIdentityBar.swift — PATCH 02
//
// Extracted from WatchRoomSupportTypes.swift per PATCH 02 spec.
//
// Shows room title, host badge, and (in tablet) the deep-link share button.
// Professional design:
//   - 14pt semibold title (was 13pt)
//   - HOST badge as pill with gold accent (was thin text)
//   - Subtle divider below (was nothing)
//   - 16pt horizontal padding (was 14pt)

import SwiftUI

struct RoomIdentityBar: View {
    let model: WatchRoomModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.roomId ?? "Plink Room")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                    .lineLimit(1)

                if let host = model.participants.first(where: { $0.userId == model.hostId }) {
                    Text("Hosted by \(host.username)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if model.isHost {
                Text("HOST")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Cinema2026.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Cinema2026.amber.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(Cinema2026.amber.opacity(0.3), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}
