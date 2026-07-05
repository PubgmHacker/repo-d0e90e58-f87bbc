import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Bubble Style Renderer (v10 — July 2026)
// ═══════════════════════════════════════════════════════════════════════
//
// Renders a chat message bubble according to its server-confirmed
// `effectiveBubbleStyle`. Three styles supported:
//
//   .default      — basic bubble, used by everyone (incl. premium users
//                   who haven't picked a custom style)
//   .cuteDuck     — Плинк+ style: yellow gradient + animated duck sprite
//                   positioned on the outer border of the frame
//   .neonCyber    — Плинк+ style: cyberpunk neon border with pulsing glow
//   .adminBubble  — Admin/Founder exclusive: matte black + animated gold
//                   neon frame. NO icon — visual distinction comes from
//                   the bubble itself (admins already have a badge).
//
// Performance: animations use SwiftUI's `phase` animation with a single
// TimelineView per style. Each bubble holds its own @State phase counter
// so multiple bubbles don't share animation state. Sprite animations
// use Canvas/TimelineView to avoid creating heavy SpriteKit scenes per
// bubble (SpriteKit is heavy — we have 100+ bubbles in a chat).
//
// Anti-tampering: this view ONLY reads `effectiveBubbleStyle` from the
// ChatMessage struct (server-confirmed). It does NOT consult any local
// preference. Even if a jailbroken client modified BubbleStylePreference,
// the rendered style would still match what the server broadcast.

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Public Entry Point
// ═══════════════════════════════════════════════════════════════════════

/// Single entry point used by RoomChatView. Routes to the appropriate
/// style renderer based on the server-confirmed `effectiveBubbleStyle`.
struct StyledChatBubble<Content: View>: View {
    let message: ChatMessage
    let isOwn: Bool  // true if the message was sent by the local user
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch message.effectiveBubbleStyle {
        case .default:
            DefaultBubble(isOwn: isOwn, content: content)
        case .cuteDuck:
            CuteDuckBubble(isOwn: isOwn, content: content)
        case .neonCyber:
            NeonCyberBubble(isOwn: isOwn, content: content)
        case .adminBubble:
            AdminBubble(content: content)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Default Bubble
// ═══════════════════════════════════════════════════════════════════════

private struct DefaultBubble<Content: View>: View {
    let isOwn: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isOwn {
                        LinearGradient(
                            colors: [Color.bioCyan, Color.bioEmerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.raveCard
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Cute Duck Bubble (Плинк+)
// ═══════════════════════════════════════════════════════════════════════

/// Yellow gradient bubble with a cute duck sprite that bobs along the
/// top-right edge of the bubble. Animation: 2.4s bob + 4s wing flap.
private struct CuteDuckBubble<Content: View>: View {
    let isOwn: Bool
    @ViewBuilder let content: () -> Content

    @State private var bobPhase: Double = 0
    @State private var wingPhase: Double = 0

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                // Yellow gradient — Plink+ signature warm palette
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.85, blue: 0.30),  // light yellow
                        Color(red: 1.0, green: 0.70, blue: 0.15),  // amber
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                // Yellow border with slight glow
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 1.0, green: 0.55, blue: 0.0).opacity(0.6), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // 🔧 Duck sprite on the outer border — bobs up/down
                CuteDuckSprite(wingPhase: wingPhase)
                    .offset(x: 12, y: -10 + bobPhase * -3)  // bob 3pt up at peak
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    bobPhase = 1.0
                }
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    wingPhase = 1.0
                }
            }
    }
}

/// Lightweight SVG-like duck drawn with SwiftUI shapes (no SpriteKit —
/// keeps per-bubble cost low for chat lists with 100+ messages).
private struct CuteDuckSprite: View {
    let wingPhase: Double  // 0..1, controls wing rotation

    var body: some View {
        ZStack {
            // Body
            Circle()
                .fill(Color(red: 1.0, green: 0.92, blue: 0.55))
                .frame(width: 22, height: 18)
            // Head
            Circle()
                .fill(Color(red: 1.0, green: 0.95, blue: 0.65))
                .frame(width: 14, height: 14)
                .offset(x: -3, y: -8)
            // Beak
            Triangle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.0))
                .frame(width: 6, height: 4)
                .offset(x: -10, y: -8)
            // Eye
            Circle()
                .fill(Color.black)
                .frame(width: 2, height: 2)
                .offset(x: -5, y: -10)
            // Wing (animated)
            Ellipse()
                .fill(Color(red: 1.0, green: 0.80, blue: 0.30))
                .frame(width: 10, height: 7)
                .rotationEffect(.degrees(wingPhase * 25))  // 0° to 25°
                .offset(x: 5, y: 2)
        }
        .frame(width: 28, height: 24)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Neon Cyber Bubble (Плинк+)
// ═══════════════════════════════════════════════════════════════════════

/// Cyberpunk-style bubble: dark glass background with pulsing neon border
/// in cyan/magenta. Animation: 1.6s pulse cycle.
private struct NeonCyberBubble<Content: View>: View {
    let isOwn: Bool
    @ViewBuilder let content: () -> Content

    @State private var pulsePhase: Double = 0

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Dark glass background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                    // Cyber grid pattern overlay (subtle)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.8 + pulsePhase * 0.2),
                                    Color.magenta.opacity(0.6 + pulsePhase * 0.3),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5 + pulsePhase * 0.5
                        )
                }
            )
            .overlay(
                // Outer neon glow — pulses
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.cyan.opacity(0.4 + pulsePhase * 0.4), lineWidth: 2)
                    .blur(radius: 3 + pulsePhase * 4)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsePhase = 1.0
                }
            }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Admin Bubble (Admin/Founder Exclusive)
// ═══════════════════════════════════════════════════════════════════════

/// Matte black bubble with animated gold neon frame. NO icon — visual
/// distinction comes purely from the bubble styling (admins already have
/// a separate badge component for icon-based identification).
///
/// Animation: 3s gold shimmer cycle around the border + subtle pulse.
private struct AdminBubble<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var shimmerPhase: Double = 0
    @State private var glowPhase: Double = 0

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Deep matte black
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.04, green: 0.04, blue: 0.06))  // near-black
                    // Subtle gold radial shimmer in the corner
                    RadialGradient(
                        colors: [
                            Color(red: 0.85, green: 0.65, blue: 0.20).opacity(0.15 + shimmerPhase * 0.20),
                            .clear,
                        ],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 80
                    )
                }
            )
            .overlay(
                // Gold gradient border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.75, blue: 0.20),  // bright gold
                                Color(red: 0.70, green: 0.50, blue: 0.10),  // dark gold
                                Color(red: 0.95, green: 0.75, blue: 0.20),  // bright gold
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .overlay(
                // Animated outer gold glow — shimmers
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Color(red: 1.0, green: 0.84, blue: 0.30)
                            .opacity(0.35 + glowPhase * 0.4),
                        lineWidth: 1.5
                    )
                    .blur(radius: 4 + glowPhase * 5)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onAppear {
                // Slow shimmer — gold moves around the border
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    shimmerPhase = 1.0
                }
                // Slower glow pulse — premium feel
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    glowPhase = 1.0
                }
            }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════════════════════════

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([
                ("default", "Привет всем! 👋", false),
                ("cute_duck", "Какой классный фильм!", false),
                ("neon_cyber", "Киберпанк-вайб активирован", false),
                ("admin_bubble", "Правила чата: будьте добры друг к другу", false),
            ], id: \.0) { (style, text, _) in
                StyledChatBubble(
                    message: ChatMessage(
                        id: style, roomID: "preview", senderID: "u", senderName: "Preview",
                        text: text, timestamp: .now, isRead: true,
                        senderAvatarURL: nil, senderRole: nil,
                        bubbleStyle: style
                    ),
                    isOwn: false
                ) {
                    Text(text)
                        .foregroundColor(style == "default" ? .white : .white)
                        .font(.system(size: 14))
                }
            }
        }
        .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
