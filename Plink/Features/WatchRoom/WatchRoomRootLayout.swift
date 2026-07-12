// Plink/Features/WatchRoom/WatchRoomRootLayout.swift — Brain Revision 3 Step 5 + 8
//
// Single structural PlayerStage OUTSIDE the layout switch.
//
// Brain: "The player appears once, outside the switch. Chrome changes around it."
// Putting `.id("plink.player.stage")` inside three different conditional parent
// trees does not guarantee SwiftUI preserves the underlying representable —
// identity is scoped by structural path. This layout puts PlayerStage at the
// ZStack root so its identity is stable across all variants.
//
// Layout variants (Portrait/Landscape/Tablet) now provide only the surrounding
// chrome (presence bar, chat, composer, drawer). The player surface is shared.
//
// Brain Revision 3 Step 8: artwork-driven palette via PaletteLoader.
// The backdrop palette is extracted asynchronously from the current video's
// thumbnail and updates when mediaThumbnailURL changes. Never captures
// YouTube/WKWebView/DRM frames — palette comes from a separate AsyncImage load.

import SwiftUI

struct WatchRoomRootLayout: View {
    @Bindable var model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    /// Brain Revision 3 Step 8: artwork-driven palette (defaults to Cinema2026).
    @State private var palette: LivingBackdropPalette = .cinema2026

    var body: some View {
        ZStack {
            // Brain Revision 3 Step 8: artwork-driven living backdrop.
            // Updates when mediaThumbnailURL changes (e.g. host replaces video).
            CompactLivingBackdrop(palette: palette)
                .ignoresSafeArea()

            // Brain Revision 3: ONE PlayerStage, outside the switch.
            // .id(model.roomID) — stable identity across layout switches.
            // variant drives corner radius only (not player identity).
            PlayerStage(model: model, ui: $ui, variant: ui.variant)
                .id(model.roomID ?? "plink.player.stage")

            // Chrome changes around the player — never replaces it.
            switch ui.variant {
            case .portrait:
                PortraitChrome(model: model, ui: $ui)
                    .transition(.opacity)
            case .landscape:
                LandscapeChrome(model: model, ui: $ui)
                    .transition(.opacity)
            case .tablet:
                TabletChrome(model: model, ui: $ui)
                    .transition(.opacity)
            }
        }
        .animation(.plinkLayout, value: ui.variant)
        // Brain Revision 3 Step 8: load palette when thumbnail URL changes.
        // Runs off the main actor (PaletteLoader is an actor), publishes on main.
        // Caches by URL so repeated loads of the same thumbnail are instant.
        .task(id: model.mediaThumbnailURL) {
            palette = await PaletteLoader.shared.palette(for: model.mediaThumbnailURL)
        }
    }
}

// MARK: - Portrait Chrome (surrounding the player, not owning it)

struct PortraitChrome: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        VStack(spacing: 0) {
            // Player sits in WatchRoomRootLayout — reserve its space here.
            Spacer().frame(height: playerHeight)

            PresenceBar(model: model)

            WatchChatView(model: model)
                .frame(maxHeight: .infinity)

            WatchChatComposer(model: model)
        }
    }

    /// Match the 16:9 player height for portrait (full-width).
    private var playerHeight: CGFloat {
        UIScreen.main.bounds.width * 9.0 / 16.0
    }
}

// MARK: - Landscape Chrome

struct LandscapeChrome: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        ZStack(alignment: .trailing) {
            // Player fills the canvas in WatchRoomRootLayout (it has .ignoresSafeArea()
            // via variant == .landscape in PlayerStage). Chrome overlays only chat drawer.
            if ui.chatDrawerVisible {
                LandscapeChatDrawer(model: model, isVisible: $ui.chatDrawerVisible)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack {
                    Spacer()
                    Button {
                        withAnimation(.plinkDrawer) {
                            ui.chatDrawerVisible = true
                        }
                    } label: {
                        Image(systemName: "message.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Cinema2026.text)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    }
                    .accessibilityLabel("Open chat")
                    .padding(.trailing, 12)
                }
            }
        }
    }
}

// MARK: - Tablet Chrome

struct TabletChrome: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        HStack(spacing: 0) {
            // Player + identity + presence live in WatchRoomRootLayout.
            // Reserve the leading column space and overlay identity/presence.
            VStack(spacing: 0) {
                Spacer().frame(height: playerHeight)
                RoomIdentityBar(model: model)
                PresenceBar(model: model)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Cinema2026.divider.opacity(0.45))
                .frame(width: 0.5)

            VStack(spacing: 0) {
                WatchChatHeader(model: model)
                WatchChatView(model: model)
                WatchChatComposer(model: model)
            }
            .frame(width: 360)
            .background(Cinema2026.background.opacity(0.95))
        }
    }

    /// Match the 16:9 player height for tablet (60% of width).
    private var playerHeight: CGFloat {
        UIScreen.main.bounds.width * 0.6 * 9.0 / 16.0
    }
}
