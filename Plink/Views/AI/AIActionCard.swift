// Plink/Views/AI/AIActionCard.swift
//
// AI Companion Pro — Confirm Actions UI Component
// Renders proposed AI actions (seek/pause/play) with confirm/cancel buttons.

import SwiftUI

// MARK: - AI Action Model

struct AIProposedAction: Identifiable, Equatable {
    let id = UUID()
    let type: ActionType
    let timestamp: TimeInterval?  // for seek
    let description: String
    let confirmationId: String?  // backend ID for confirm endpoint

    enum ActionType: String, Codable {
        case seek
        case pause
        case play
        case createRoom
        case buildQueue
    }
}

// MARK: - AI Action Card View

struct AIActionCard: View {
    let action: AIProposedAction
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            // AI orb icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: actionIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0E1113))
            }
            .accessibilityHidden(true)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text("AI предлагает")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2DE2E6))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(action.description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Cinema2026.text)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            // Buttons
            HStack(spacing: 6) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Отклонить")
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0E1113))
                        .frame(width: 30, height: 30)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
                .accessibilityLabel("Подтвердить")
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hex: 0x2DE2E6).opacity(0.3), lineWidth: 1)
                )
        )
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .bottom).combined(with: .opacity)
        )
    }

    // MARK: - Action icon

    private var actionIcon: String {
        switch action.type {
        case .seek: return "forward.fill"
        case .pause: return "pause.fill"
        case .play: return "play.fill"
        case .createRoom: return "plus.circle.fill"
        case .buildQueue: return "list.bullet.rectangle"
        }
    }
}

// MARK: - AI Action Executor

/// Executes confirmed AI actions on the room model.
@MainActor
final class AIActionExecutor {
    weak var roomModel: WatchRoomModel?

    init(roomModel: WatchRoomModel?) {
        self.roomModel = roomModel
    }

    func execute(_ action: AIProposedAction) async {
        guard let roomModel else { return }

        switch action.type {
        case .seek:
            if let timestamp = action.timestamp {
                roomModel.seek(to: timestamp)
                AnalyticsService.shared.logAIActionExecuted(type: "seek", timestamp: timestamp)
            }

        case .pause:
            roomModel.pause()
            AnalyticsService.shared.logAIActionExecuted(type: "pause", timestamp: nil)

        case .play:
            roomModel.play()
            AnalyticsService.shared.logAIActionExecuted(type: "play", timestamp: nil)

        case .createRoom, .buildQueue:
            // Handle via callback (these need UI navigation)
            break
        }

        // Confirm with backend if confirmationId exists
        if let confirmationId = action.confirmationId {
            await confirmWithBackend(confirmationId: confirmationId)
        }
    }

    private func confirmWithBackend(confirmationId: String) async {
        // POST /api/ai/confirm-action { confirmationId }
        do {
            try await APIClient.shared.confirmAIAction(confirmationId: confirmationId)
        } catch {
            // Silent fail — action already executed locally
            print("[AIActionExecutor] Failed to confirm with backend: \(error)")
        }
    }
}

// MARK: - Analytics Extension

extension AnalyticsService {
    func logAIActionExecuted(type: String, timestamp: TimeInterval?) {
        var params: [String: Any] = ["action_type": type]
        if let timestamp {
            params["timestamp"] = timestamp
        }
        logEvent("ai_action_executed", parameters: params)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AI Action Card — Seek") {
    AIActionCard(
        action: AIProposedAction(
            type: .seek,
            timestamp: 1234.5,
            description: "Перемотать на 20:34 где главный момент?",
            confirmationId: nil
        ),
        onConfirm: { print("Confirmed") },
        onDismiss: { print("Dismissed") }
    )
    .padding()
    .background(Cinema2026.background)
    .preferredColorScheme(.dark)
}

#Preview("AI Action Card — Pause") {
    AIActionCard(
        action: AIProposedAction(
            type: .pause,
            timestamp: nil,
            description: "Поставить паузу для обсуждения сцены?",
            confirmationId: nil
        ),
        onConfirm: { print("Confirmed") },
        onDismiss: { print("Dismissed") }
    )
    .padding()
    .background(Cinema2026.background)
    .preferredColorScheme(.dark)
}
#endif
