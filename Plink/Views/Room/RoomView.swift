import SwiftUI
import AVKit

// MARK: - Room View v4 — Rave-style Layout
///
/// Портрет:
/// ┌──────────────────────┐
/// │      Ambilight       │
/// │   ┌──────────────┐   │  ← видео 16:9, ~70% ширины, центрировано
/// │   │    VIDEO     │   │     контролы по центру видео
/// │   │  (controls)  │   │     аватары в правом верхнем углу видео
/// │   └──────────────┘   │
/// │                      │
/// │   ┌──────────────┐   │  ← чат (оставшееся пространство)
/// │   │    CHAT      │   │     всегда виден
/// │   └──────────────┘   │
/// └──────────────────────┘
///
/// Ландшафт:
/// ┌──────────────────────┐
/// │ VIDEO (full screen)  │  ← видео на весь экран
/// │            ┌────────┐│  ← чат выезжает справа поверх
/// │            │  CHAT  ││
/// │            └────────┘│
/// └──────────────────────┘
struct RoomView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let room: Room

    @State private var viewModel: RoomViewModel?
    @State private var syncManager: RoomSyncManager?
    @State private var voiceChat: VoiceChatService?
    // UI State
    @State private var showControls = true
    @State private var showChatPanel = true  // landscape: чат открыт по умолчанию
    @State private var reactionTrigger: ReactionTrigger?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showEmojiPicker = false
    @State private var shareSheetPresented = false
    @State private var showParticipants = false
    /// YouTube-style: кнопка fullscreen разворачивает видео на весь экран
    /// с авторотацией в ландшафт. ВАЖНО: используется ТОЛЬКО для управления
    /// ориентацией устройства, а НЕ для выбора layout (layout зависит от геометрии).
    @State private var isFullscreenMode = false
    /// 🔧 v35.4: prevents resetToPortrait on re-entrant onAppear (fullscreen toggle).
    @State private var hasRoomAppeared = false
    /// 🔧 v32.13: video ended — shows completion screen with replay/exit buttons.
    @State private var isVideoEnded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    // 🔧 FIX C7: Receive shared authenticated APIClient from environment
    @EnvironmentObject private var apiClient: APIClient
    // 🔧 FIX 1.4: Receive shared WebSocketClient from environment — already authenticated
    // with JWT token. Was: setupViewModel created a new WebSocketClient() without token →
    // WS connect without auth → 401 → reconnect loop.
    @EnvironmentObject private var sharedWsClient: WebSocketClient

    private let controlsHideDelay: UInt64 = 3_000_000_000

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height || isFullscreenMode

            ZStack {
                AmbilightBackground()

                if let viewModel {
                    // 🔧 v34.12: SINGLE layout tree — no if/else switch.
                    // SwiftUI was tearing down portraitLayout → creating landscapeLayout
                    // → WKWebView moved between view hierarchies → WebContent rendering
                    // context destroyed → video black screen (audio still playing).
                    // Now ONE VStack adapts: portrait = video top + chat bottom,
                    // landscape = video fullscreen + chat overlay.
                    unifiedLayout(viewModel: viewModel, geo: geo, isLandscape: isLandscape)
                } else {
                    ProgressView(loc.string(.roomConnecting))
                        .tint(.ravePrimary)
                        .onAppear { setupViewModel() }
                }

                ReactionSpriteOverlay(reactionTrigger: $reactionTrigger)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        // 🔧 FIX: hide tabbar completely in RoomView — was removed for "delay"
        // but that caused tabbar to appear in landscape when swiping chat.
        // User: 'в горизонтальном если свайпать чат = появляется таббар'.
        .toolbar(.hidden, for: .tabBar)
        // 🔧 FIX v2 (July 2026): prevent interactive swipe-down dismissal of the
        // modal RoomView. Combined with the fullScreenCover presentation in
        // MainTabView, this kills ALL system edge-swipe paths that previously
        // caused 'swipe left → tabbar appears → screen rotates → room closes'.
        .interactiveDismissDisabled(true)
        .task {
            guard let viewModel else { return }
            await viewModel.joinRoomFlow()
            // 🔧 FIX M10: Removed redundant voiceChat.startCall call —
            // joinRoomFlow already calls voiceChat.startCall(roomId:) at line 102.
            // The second call was idempotent (VoiceChatService.startCall has guard
            // !isActive), but its try? swallowed any legitimate error from setup.

            // Восстановление позиции (авто-пауза → продолжить с того же места)
            let savedPosition = UserDefaults.standard.double(forKey: "room_position_\(room.id)")
            if savedPosition > 0 {
                viewModel.syncEngine.seek(to: savedPosition)
            }
        }
        .onAppear {
            // 🔧 v35.5: NO resetToPortrait here — it fires on re-entrant
            // onAppear during fullscreen toggle and cancels lockToLandscape.
            // Orientation is locked in setupViewModel (portrait) and unlocked
            // only in explicit room-exit handlers.
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 🔧 v35.5: NO resetToPortrait on scenePhase change.
            // This was firing during lockToLandscape() → cancelling it.
        }
        .onDisappear {
            // 🔧 v35.3: ONLY save position. NO orientation reset here.
            // Orientation unlock + forcePortrait live in room-exit handlers.
            guard let viewModel else { return }
            let position = viewModel.syncEngine.currentTime
            let roomID = room.id
            UserDefaults.standard.set(position, forKey: "room_position_\(roomID)")
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // 🔧 Pack v3: Убран скрытый chevron.left (сдвигал плеер вниз)
            // Swipe-back работает через NavigationStack автоматически
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $shareSheetPresented) {
            if let url = URL(string: "https://plink.app/join/\(room.code)") {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showParticipants) {
            ParticipantListView(room: room)
        }
    }

    // MARK: - Unified Layout (v34.21) — TRULY IMMUTABLE view tree
    //
    // 🔧 v34.19 had a subtle bug: `if !isLandscape { RoomChatView... }` changed
    // the number of VStack children when toggling fullscreen. SwiftUI assigned
    // new identity to the remaining videoSection child → UIViewRepresentable
    // got makeUIView again → WKWebView moved to new superview → rendering
    // context destroyed → video reset.
    //
    // v34.21 FIX: Chat is ALWAYS in the VStack, height 0 in landscape.
    // View tree structure NEVER changes — only frame heights do.

    @ViewBuilder
    private func unifiedLayout(viewModel: RoomViewModel, geo: GeometryProxy, isLandscape: Bool) -> some View {
        let videoWidth = geo.size.width
        let videoHeight: CGFloat = isLandscape ? geo.size.height : (geo.size.width * 9.0 / 16.0)
        let chatHeight: CGFloat = isLandscape ? 0 : max(geo.size.height - videoHeight - 8, 0)
        let roomTheme = PremiumStatusManager.shared.selectedRoomTheme

        // 🔧 v37.1: VStack with FIXED video height — chat fills remainder.
        // Video height is CONSTANT (screen width * 9/16) regardless of isLandscape.
        // In landscape: videoHeight = screen height (full), chat height = 0.
        // VStack re-layout only changes chat height, NOT video height →
        // VideoContainerView frame stays same → no makeUIView re-trigger.
        VStack(spacing: 0) {
            videoSection(
                viewModel: viewModel,
                videoWidth: videoWidth,
                videoHeight: videoHeight,
                isFullscreen: isLandscape
            )
            .frame(width: videoWidth, height: videoHeight)

            RoomChatView(
                messages: syncManager?.chatMessages ?? viewModel.messages,
                chatText: chatTextBinding,
                onSend: sendMessage,
                currentUserID: viewModel.currentUserId,
                mode: .portrait
            )
            .frame(width: videoWidth, height: chatHeight)
            .background(
                Group {
                    if roomTheme.hasPlayerBorder { roomTheme.chatBackground } else { Color.clear }
                }
            )
            .padding(.horizontal, isLandscape ? 0 : 8)
            .padding(.bottom, isLandscape ? 0 : 8)
            .opacity(isLandscape ? 0 : 1)
        }
        // Landscape chat overlay — ALWAYS present, hidden via opacity in portrait
        .overlay {
            ZStack {
                RoomChatView(
                    messages: syncManager?.chatMessages ?? viewModel.messages,
                    chatText: chatTextBinding,
                    onSend: sendMessage,
                    currentUserID: viewModel.currentUserId,
                    mode: .landscape,
                    isPanelOpen: $showChatPanel
                )
                .ignoresSafeArea()

                if !showChatPanel {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showChatPanel = true
                                }
                            } label: {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .opacity(isLandscape ? 1 : 0)
            .allowsHitTesting(isLandscape)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { handleDoubleTap() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 80)
                .onEnded { value in
                    guard isLandscape else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) * 2 else { return }
                    if !showChatPanel && horizontal < -80 {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showChatPanel = true
                        }
                    } else if showChatPanel && horizontal > 80 {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showChatPanel = false
                        }
                    }
                }
        )
    }

    // MARK: - Portrait Layout (legacy — not used, kept for reference)

    @ViewBuilder
    private func portraitLayout(viewModel: RoomViewModel, geo: GeometryProxy) -> some View {
        let screenWidth = geo.size.width
        let videoWidth = screenWidth
        let videoHeight = videoWidth * 9.0 / 16.0
        let chatHeight = geo.size.height - videoHeight - 8
        let roomTheme = PremiumStatusManager.shared.selectedRoomTheme

        VStack(spacing: 0) {
            videoSection(
                viewModel: viewModel,
                videoWidth: videoWidth,
                videoHeight: videoHeight,
                isFullscreen: false
            )

            RoomChatView(
                messages: syncManager?.chatMessages ?? viewModel.messages,
                chatText: chatTextBinding,
                onSend: sendMessage,
                currentUserID: viewModel.currentUserId,
                mode: .portrait
            )
            .frame(height: max(chatHeight, 100))
            .background(
                Group {
                    if roomTheme.hasPlayerBorder {
                        roomTheme.chatBackground
                    } else {
                        Color.clear
                    }
                }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { handleDoubleTap() }
        )
    }

    // MARK: - Landscape Layout

    @ViewBuilder
    private func landscapeLayout(viewModel: RoomViewModel, geo: GeometryProxy) -> some View {
        ZStack {
            videoSection(
                viewModel: viewModel,
                videoWidth: geo.size.width,
                videoHeight: geo.size.height,
                isFullscreen: true
            )

            RoomChatView(
                messages: syncManager?.chatMessages ?? viewModel.messages,
                chatText: chatTextBinding,
                onSend: sendMessage,
                currentUserID: viewModel.currentUserId,
                mode: .landscape,
                isPanelOpen: $showChatPanel
            )
            .ignoresSafeArea()

            if !showChatPanel {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showChatPanel = true
                            }
                        } label: {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { handleDoubleTap() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 80)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) * 2 else { return }
                    if !showChatPanel && horizontal < -80 {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showChatPanel = true
                        }
                    }
                    else if showChatPanel && horizontal > 80 {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showChatPanel = false
                        }
                    }
                }
        )
    }

    // MARK: - Video Section (видео + оверлеи)
    //
    // 🔧 v38 FIX (CRITICAL): Extract the media-reading branch into a dedicated
    // subview `VideoSectionContent` that observes `SyncEngine` directly via
    // `@ObservedObject`. This is REQUIRED because:
    //
    //   - `RoomViewModel` is `@Observable` (new macro)
    //   - `SyncEngine` is legacy `ObservableObject`
    //   - When RoomView reads `viewModel.syncEngine.currentMediaItem`, the
    //     @Observable macro tracks the access to `viewModel.syncEngine` (the
    //     reference), but does NOT subscribe to SyncEngine's `objectWillChange`
    //     publisher. So changes to `currentMediaItem` / `isPlaying` / `currentTime`
    //     / `duration` on SyncEngine never trigger a RoomView re-render.
    //   - Symptom: WS connects → loadMedia sets currentMediaItem → logs confirm
    //     `currentMediaItem == nil: false` → but `makeUIView` is never called
    //     because videoSection still sees `currentMediaItem == nil` from the
    //     last render.
    //
    // The fix: a subview with `@ObservedObject var syncEngine: SyncEngine`
    // explicitly subscribes to `objectWillChange`, so any @Published change on
    // SyncEngine triggers a re-render of the subview. The non-SyncEngine-dependent
    // parts (close button, completion screen) stay in the parent for free.

    @ViewBuilder
    private func videoSection(
        viewModel: RoomViewModel,
        videoWidth: CGFloat,
        videoHeight: CGFloat,
        isFullscreen: Bool
    ) -> some View {
        ZStack {
            // 🔧 v38: delegate media rendering to a subview that observes SyncEngine.
            VideoSectionContent(
                syncEngine: viewModel.syncEngine,
                videoPlaceholder: { AnyView(videoPlaceholder) }
            )

            // Minimal floating close button (top-left) + fullscreen button (top-right)
            VStack {
                HStack {
                    // 🔧 v39: X button — ALWAYS closes the room (was: dual-purpose
                    // close-room / exit-fullscreen which was confusing).
                    Button {
                        HapticManager.impact(.light)
                        OrientationManager.shared.unlockOrientation()
                        OrientationManager.shared.forcePortrait()
                        syncManager?.disconnect()
                        Task {
                            await voiceChat?.endCall()
                            await viewModel.cleanupFlow()
                            WebViewControl.shared.unregister()
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Spacer()
                    // 🔧 v39: Dedicated fullscreen toggle button.
                    // v37 removed ControlsOverlay (which had the fullscreen button)
                    // → user had no way to enter fullscreen. This button calls
                    // enterFullscreen() / exitFullscreen() which lock orientation
                    // to landscape / portrait respectively.
                    Button {
                        HapticManager.impact(.light)
                        if isFullscreen {
                            exitFullscreen()
                        } else {
                            enterFullscreen()
                        }
                    } label: {
                        Image(systemName: isFullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    ParticipantBadge(count: viewModel.room.participantCount)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                Spacer()
            }
            .allowsHitTesting(true)

            // Completion screen
            if isVideoEnded {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56)).foregroundColor(.bioEmerald)
                        Text("Видео завершено")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        HStack(spacing: 16) {
                            Button {
                                HapticManager.impact(.medium)
                                viewModel.syncEngine.seek(to: 0)
                                WebViewControl.shared.play()
                                withAnimation(.easeInOut(duration: 0.3)) { isVideoEnded = false }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise").font(.system(size: 22))
                                    Text("Сначала").font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.white).frame(width: 100, height: 70)
                                .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                HapticManager.impact(.medium)
                                OrientationManager.shared.unlockOrientation()
                                OrientationManager.shared.forcePortrait()
                                syncManager?.disconnect()
                                Task {
                                    await voiceChat?.endCall()
                                    await viewModel.cleanupFlow()
                                    WebViewControl.shared.unregister()
                                }
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "xmark").font(.system(size: 22))
                                    Text("Выйти").font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.white).frame(width: 100, height: 70)
                                .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                .transition(.opacity).zIndex(100)
            }
        }
        .frame(width: videoWidth, height: videoHeight)
        .clipped()
    }

    private var videoPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.ravePrimary)
                    .scaleEffect(1.2)
                Text(loc.string(.roomLoading))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Controls Visibility

    private func toggleControls() {
        showControls.toggle()
        if showControls { resetControlsTimer() }
    }

    // MARK: - Fullscreen State Reset

    /// Сброс fullscreen-состояния — вызывается при onAppear и возврате из background.
    private func resetToPortrait() {
        // 🔧 v34.2: don't reset if user is in fullscreen mode
        guard !isFullscreenMode else { return }
        isFullscreenMode = false
        showChatPanel = true
        showEmojiPicker = false
        OrientationManager.shared.lockToPortrait()
    }

    // MARK: - Fullscreen (с вращением устройства)
    //
    // 🔧 v34.24: fullscreen = вращение устройства + layout.
    // Ключевое: onDisappear больше НЕ сбрасывает ориентацию (v34.22),
    // поэтому lockToLandscape больше не отменяется mid-toggle.

    private func enterFullscreen() {
        print("📱📱📱 enterFullscreen START — isFullscreenMode was: \(isFullscreenMode)")
        // 🔧 v41: Prepare WKWebView for full reload BEFORE the layout change.
        // This saves the current playback position and sets needsFullReload = true.
        // When SwiftUI re-evaluates videoSection (due to isFullscreenMode change),
        // makeUIView will see needsFullReload=true, destroy the old WKWebView,
        // create a new one, and restore the saved position.
        // This avoids "MediaSourcePrivateRemote object has been destroyed"
        // (black screen after rotation) — the rendering context is permanently
        // dead after re-parenting, so we MUST recreate the WKWebView.
        WebViewControl.shared.prepareForFullReload()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isFullscreenMode = true
            showControls = true
        }
        print("📱📱📱 enterFullscreen — calling lockToLandscape, isFullscreenMode now: \(isFullscreenMode)")
        OrientationManager.shared.lockToLandscape()
        resetControlsTimer()
    }

    private func exitFullscreen() {
        print("📱 exitFullscreen: isFullscreenMode = false + rotating to portrait")
        // 🔧 v41: Same as enterFullscreen — prepare for full reload.
        WebViewControl.shared.prepareForFullReload()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isFullscreenMode = false
            showControls = true
        }
        OrientationManager.shared.lockToPortrait()
        resetControlsTimer()
    }

    private func resetControlsTimer() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: controlsHideDelay)
            await MainActor.run {
                if !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showControls = false
                    }
                }
            }
        }
    }

    // MARK: - Reactions

    private func handleDoubleTap() {
        let emojis = ["❤️", "🔥", "😂", "👍", "🎉"]
        triggerReaction(emoji: emojis.randomElement() ?? "❤️")
    }

    /// 🔧 FIX 5.7: Throttle reactions to prevent spam (max 2/sec)
    @State private var lastReactionTime: Date = .distantPast
    private let reactionThrottle: TimeInterval = 0.5

    private func triggerReaction(emoji: String) {
        let now = Date()
        guard now.timeIntervalSince(lastReactionTime) >= reactionThrottle else { return }
        lastReactionTime = now
        HapticManager.impact(.soft)
        reactionTrigger = ReactionTrigger(
            point: CGPoint(x: UIScreen.main.bounds.width / 2,
                          y: UIScreen.main.bounds.height * 0.35),
            emoji: emoji
        )
        syncManager?.sendReaction(emoji: emoji, senderId: viewModel?.currentUserId ?? "unknown", senderName: viewModel?.room.hostName ?? "You")
    }

    // MARK: - Chat

    private var chatTextBinding: Binding<String> {
        Binding(
            get: { viewModel?.chatText ?? "" },
            set: { viewModel?.chatText = $0 }
        )
    }

    private func sendMessage() {
        guard let viewModel, let syncManager else { return }
        let text = viewModel.chatText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        // 🔧 Pack v3: Реальные данные отправителя (не "You")
        let userName = UserDefaults.standard.string(forKey: "plink_current_username") ?? "You"
        let userRole = UserDefaults.standard.string(forKey: "plink_current_user_role") ?? "USER"

        let message = ChatMessage(
            id: UUID().uuidString,
            roomID: room.id,
            senderID: viewModel.currentUserId,
            senderName: userName,
            text: text,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil,
            senderRole: userRole
        )
        syncManager.sendChatMessage(message)
        viewModel.messages.append(message)
        viewModel.chatText = ""
    }

    // MARK: - Setup (DI)

    private func setupViewModel() {
        // 🔧 FIX C7 + H9: Use shared authenticated APIClient from environment
        let api = apiClient
        // 🔧 FIX 1.4: Use SHARED WebSocketClient — already connected + authenticated with JWT.
        // Was: WebSocketClient() — new instance without token → 401 → reconnect loop.
        let wsClient = sharedWsClient
        let roomService = RoomService(api: api)
        let authService = AuthService(api: api)

        // 🔧 FIX C7: Resolve real currentUserId from saved user profile
        // (was: hardcoded "current_user" — isHost was always false)
        let currentUserId: String = {
            if let data = UserDefaults.standard.data(forKey: "rave_saved_user"),
               let user = try? JSONDecoder().decode(User.self, from: data) {
                return user.id
            }
            return UUID().uuidString  // fallback for unauthenticated (shouldn't happen)
        }()
        let isHost = room.hostID == currentUserId

        // 🔧 FIX C8: Resolve real hostIsPremium from PremiumStatusManager
        // (was: hardcoded false — premium hosts still saw ads)
        let hostIsPremium = PremiumStatusManager.shared.isPremium

        let signaling = SignalingClient(ws: wsClient)
        let voiceChat = VoiceChatService(signaling: signaling, localPeerId: currentUserId)

        let syncEngine = SyncEngine(
            wsClient: wsClient,
            roomID: room.id,
            userID: currentUserId,
            isHost: isHost
        )

        // 🔧 v32.10: wire WebView time updates to SyncEngine.currentTime.
        // This updates the seek bar + time display without triggering seeks.
        WebViewControl.shared.onTimeUpdate = { time in
            syncEngine.updateCurrentTimeFromWebView(time)
        }
        // 🔧 v32.11: wire WebView duration updates to SyncEngine.duration.
        // Without this, seek() clamps to min(time, 0) = 0 → always seeks to start.
        WebViewControl.shared.onDurationUpdate = { duration in
            syncEngine.updateDurationFromWebView(duration)
        }
        // 🔧 v32.12: wire player ready event — hides loading overlay.
        WebViewControl.shared.onPlayerReady = {
            NotificationCenter.default.post(name: .youtubePlayerReady, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WebViewControl.shared.unmute()
            }
            DispatchQueue.main.async {
                isVideoEnded = false
            }
        }
        // 🔧 v32.13: wire player ended event
        WebViewControl.shared.onPlayerEnded = {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVideoEnded = true
                }
            }
        }
        // 🔧 v35.6: wire play state change → SyncEngine.isPlaying
        WebViewControl.shared.onPlayStateChange = { playing in
            syncEngine.setIsPlaying(playing)
        }

        let vm = RoomViewModel(
            room: room,
            currentUserId: currentUserId,
            wsClient: wsClient,
            roomService: roomService,
            authService: authService,
            syncEngine: syncEngine,
            voiceChat: voiceChat
        )
        // Propagate premium flag for ad logic (C10 fix uses this)
        vm.hostIsPremium = hostIsPremium

        let manager = RoomSyncManager(wsClient: wsClient, roomID: room.id)
        manager.onPlayCommand = { pos in
            vm.syncEngine.seek(to: pos)
            if !vm.syncEngine.isPlaying { vm.syncEngine.togglePlayPause() }
        }
        manager.onPauseCommand = { pos in
            vm.syncEngine.seek(to: pos)
            if vm.syncEngine.isPlaying { vm.syncEngine.togglePlayPause() }
        }
        manager.onSeekCommand = { pos in vm.syncEngine.seek(to: pos) }
        manager.onReactionReceived = { HapticManager.impact(.soft) }
        manager.connect()

        viewModel = vm
        syncManager = manager
        self.voiceChat = voiceChat
    }
}

// MARK: - Video Section Content (v38 — observes SyncEngine directly)
//
// 🔧 v38 CRITICAL FIX: This subview exists ONLY to make SwiftUI subscribe to
// SyncEngine's `objectWillChange` publisher. RoomView is `@Observable`-driven
// (via RoomViewModel), but SyncEngine is the legacy `ObservableObject` protocol.
// When the parent reads `viewModel.syncEngine.currentMediaItem`, the @Observable
// macro tracks the access to `viewModel.syncEngine` (the reference) but does
// NOT subscribe to SyncEngine's `objectWillChange`. The result: SyncEngine's
// @Published changes (currentMediaItem, isPlaying, currentTime, duration) never
// triggered a RoomView re-render — `makeUIView` was never called even though
// `currentMediaItem` was set (confirmed in logs: "currentMediaItem == nil: false"
// immediately followed by NO `🔧🔧🔧 makeUIView CALLED` log).
//
// By declaring `@ObservedObject var syncEngine: SyncEngine` here, SwiftUI
// subscribes to `objectWillChange` and re-renders this subview whenever any
// @Published property on SyncEngine changes. The parent passes the same
// SyncEngine instance; the subview reads currentMediaItem / isPlaying / etc.
// directly from the observed reference.
private struct VideoSectionContent: View {
    @ObservedObject var syncEngine: SyncEngine
    let videoPlaceholder: () -> AnyView

    var body: some View {
        Group {
            if let mediaItem = syncEngine.currentMediaItem,
               !mediaItem.streamURL.isEmpty {
                VideoContainerView(
                    mediaURL: mediaItem.streamURL,
                    playbackMode: mediaItem.effectivePlaybackMode,
                    isPlaying: syncEngine.isPlaying,
                    currentTime: syncEngine.currentTime,
                    duration: syncEngine.duration,
                    onTogglePlay: { syncEngine.togglePlayPause() },
                    onSeek: { pos in syncEngine.seek(to: pos) }
                )
                .onAppear {
                    print("🎬 v38: VideoSectionContent — rendering VideoContainerView for streamURL=\(mediaItem.streamURL.prefix(80))")
                }
            } else {
                videoPlaceholder()
            }
        }
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
