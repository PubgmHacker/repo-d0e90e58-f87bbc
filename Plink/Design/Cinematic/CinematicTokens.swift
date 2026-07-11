// Plink/Design/Cinematic/CinematicTokens.swift — Unified Cinematic UI
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §1: Design tokens
//
// CinemaColor replaces PlinkRave for the main app shell (Home, Rooms,
// Settings, Onboarding, Paywall). WatchRoom keeps PlinkRave tokens —
// the room has its own purple-neon aesthetic that's separate from the
// app's cinematic dark palette.
//
// Rule: Violet (CinemaColor.plink) only on CTA, selected state, progress,
// focus. Artwork provides the rest of the color.

import SwiftUI

public enum CinemaColor {
    public static let void = Color(hex: 0x090A0E)
    public static let background = Color(hex: 0x0E1016)
    public static let surface = Color(hex: 0x151821)
    public static let raised = Color(hex: 0x1D212C)
    public static let divider = Color(hex: 0x2B303D)
    public static let text = Color(hex: 0xF3F1ED)
    public static let secondary = Color(hex: 0xAAA7A2)
    public static let tertiary = Color(hex: 0x77767A)

    public static let plink = Color(hex: 0xA970FF)
    public static let plinkPressed = Color(hex: 0x8754D9)
    public static let live = Color(hex: 0x58D68D)
    public static let warning = Color(hex: 0xE9B35B)
    public static let danger = Color(hex: 0xE85D75)

    public static let primaryAction = LinearGradient(
        colors: [Color(hex: 0xB47BFF), Color(hex: 0x8A5CF0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public enum CinemaSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum CinemaRadius {
    public static let poster: CGFloat = 12
    public static let control: CGFloat = 14
    public static let panel: CGFloat = 20
}

public extension View {
    func cinematicScreen() -> some View {
        self
            .foregroundStyle(CinemaColor.text)
            .background(CinemaColor.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}

// MARK: - Button styles

struct CinematicPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CinemaColor.void)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                CinemaColor.primaryAction,
                in: RoundedRectangle(cornerRadius: CinemaRadius.control, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Reusable views

struct PosterImage: View {
    let url: String?

    var body: some View {
        if let url = url, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(CinemaColor.surface)
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle().fill(CinemaColor.surface)
                @unknown default:
                    Rectangle().fill(CinemaColor.surface)
                }
            }
        } else {
            Rectangle().fill(CinemaColor.surface)
                .overlay(
                    Image(systemName: "film")
                        .foregroundStyle(CinemaColor.tertiary)
                )
        }
    }
}

struct ParticipantAvatarStack: View {
    let participants: [UserPreview]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(participants.prefix(4)) { participant in
                Circle()
                    .fill(CinemaColor.raised)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text(String(participant.username.prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CinemaColor.secondary)
                    )
                    .overlay(Circle().stroke(CinemaColor.background, lineWidth: 2))
            }
            if participants.count > 4 {
                Text("+\(participants.count - 4)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CinemaColor.secondary)
                    .frame(width: 22, height: 22)
                    .background(CinemaColor.raised, in: Circle())
                    .overlay(Circle().stroke(CinemaColor.background, lineWidth: 2))
            }
        }
    }
}
