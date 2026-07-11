// SyncQuality moved from SyncState.swift (deleted in legacy cleanup)
import SwiftUI

enum SyncQuality: String, Sendable {
    case synced, syncing, lagging, offline
    var icon: String {
        switch self {
        case .synced: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .lagging: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }
    var color: Color {
        switch self {
        case .synced: return .green
        case .syncing: return .blue
        case .lagging: return .orange
        case .offline: return .red
        }
    }
}

// MARK: - Sync Indicator Component
/// Visual indicator showing the quality of synchronization between participants.
/// Used in room top bar and overlay.
struct SyncIndicatorView: View {
    let quality: SyncQuality

    var body: some View {
        HStack(spacing: 6) {
            // Animated icon
            Image(systemName: quality.icon)
                .font(.caption2)
                .symbolEffect(.pulse, options: .repeating, isActive: quality == .syncing)

            Text(quality.rawValue.capitalized)
                .font(.caption2.bold())
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: quality)
    }

    private var color: Color {
        switch quality {
        case .synced: return .raveGreen
        case .syncing: return .raveWarning
        case .lagging: return .raveDanger
        case .offline: return .raveDanger
        }
    }
}

// MARK: - Voice Chat Toggle Component
struct VoiceChatToggle: View {
    let isActive: Bool
    let isMuted: Bool
    let onToggle: () -> Void
    let onMute: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Main toggle
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isActive ? "waveform" : "waveform.slash")
                    Text(isActive ? "Voice On" : "Join Voice")
                        .font(.caption.bold())
                }
                .foregroundColor(isActive ? .raveGreen : .raveTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.raveCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.raveGreen : Color.raveSurface, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isActive)
            }

            // Mute button (only when active)
            if isActive {
                Button(action: onMute) {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.subheadline)
                        .foregroundColor(isMuted ? .raveDanger : .raveGreen)
                        .frame(width: 36, height: 36)
                        .background(Color.raveCard)
                        .clipShape(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Room Code Share View
struct RoomCodeShareView: View {
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Share this code")
                .font(.caption)
                .foregroundColor(.raveTextSecondary)

            // Code display
            Text(code)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(.ravePrimary)
                .tracking(8)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.raveCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.ravePrimary.opacity(0.3), lineWidth: 2)
                )

            Button {
                UIPasteboard.general.string = code
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    Text(copied ? "Copied!" : "Copy Code")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(copied ? Color.raveGreen : Color.ravePrimary)
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.2), value: copied)
            }
        }
    }
}
