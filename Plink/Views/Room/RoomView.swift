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
            // Layout полностью зависит от фактической геометрии, а не от isFullscreenMode.
            // Это устраняет баг растягивания чата при возврате из background.
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                // ── 1. Ambilight фон (весь экран) ────────────────────
                AmbilightBackground()

                // ── 2. Контент ────────────────────────────────────────
                if let viewModel {
                    if isLandscape {
                        landscapeLayout(viewModel: viewModel, geo: geo)
                    } else {
                        portraitLayout(viewModel: viewModel, geo: geo)
                    }
                } else {
                    ProgressView(loc.string(.roomConnecting))
                        .tint(.ravePrimary)
                        .onAppear { setupViewModel() }
                }

                // ── 3. SpriteKit реакции ──────────────────────────────
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
            resetToPortrait()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // КЛЮЧЕВОЙ ФИКС: при возврате из background принудительно сбрасываем
            // ориентацию и fullscreen-режим, иначе чат растягивается.
            if newPhase == .active {
                resetToPortrait()
            }
        }
        .onDisappear {
            // 🔧 FIX v2 (July 2026): release the AppDelegate orientation lock so the
            // rest of the app can rotate freely. forcePortrait() alone is not enough
            // — the lock stays active and would constrain other screens.
            OrientationManager.shared.unlockOrientation()
            OrientationManager.shared.forcePortrait()

            guard let viewModel else { return }
            syncManager?.disconnect()

            // Авто-пауза + сохранение позиции (через UserDefaults)
            let position = viewModel.syncEngine.currentTime
            let roomID = room.id
            UserDefaults.standard.set(position, forKey: "room_position_\(roomID)")

            Task {
                await voiceChat?.endCall()
                await viewModel.cleanupFlow()
            }
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

    // MARK: - Portrait Layout

    @ViewBuilder
    private func portraitLayout(viewModel: RoomViewModel, geo: GeometryProxy) -> some View {
        let screenWidth = geo.size.width
        let videoWidth = screenWidth
        let videoHeight = videoWidth * 9.0 / 16.0
        let chatHeight = geo.size.height - videoHeight - 8
        // 🔧 PREMIUM THEME: chat background gradient from selected room theme
        let roomTheme = PremiumStatusManager.shared.selectedRoomTheme

        VStack(spacing: 0) {
            // Видео 16:9 + контролы + marquee
            videoSection(
                viewModel: viewModel,
                videoWidth: videoWidth,
                videoHeight: videoHeight,
                isFullscreen: false
            )

            // Чат — оставшееся пространство
            RoomChatView(
                messages: syncManager?.chatMessages ?? viewModel.messages,
                chatText: chatTextBinding,
                onSend: sendMessage,
                currentUserID: viewModel.currentUserId,
                mode: .portrait
            )
            .frame(height: max(chatHeight, 100))
            // 🔧 PREMIUM THEME: apply chat background gradient
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
            // 🔧 Pack v3: Убран DragGesture — конфиликтовал с клавиатурой и скроллом.
            // Клавиатура убирается свайпом вниз через .scrollDismissesKeyboard(.interactively)
            // внутри RoomChatView.
        }
        .contentShape(Rectangle())
        // 🔧 v32.9: tap handling moved inside videoSection (transparent tap layer)
        // to catch taps that WKWebView would otherwise swallow.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { handleDoubleTap() }
        )
    }

    // MARK: - Landscape Layout

    @ViewBuilder
    private func landscapeLayout(viewModel: RoomViewModel, geo: GeometryProxy) -> some View {
        ZStack {
            // Видео на весь экран
            videoSection(
                viewModel: viewModel,
                videoWidth: geo.size.width,
                videoHeight: geo.size.height,
                isFullscreen: true
            )

            // Чат выезжает справа поверх
            RoomChatView(
                messages: syncManager?.chatMessages ?? viewModel.messages,
                chatText: chatTextBinding,
                onSend: sendMessage,
                currentUserID: viewModel.currentUserId,
                mode: .landscape,
                isPanelOpen: $showChatPanel
            )
            .ignoresSafeArea()

            // Кнопка вызова чата (когда свёрнут)
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
        .contentShape(Rectangle())
        // 🔧 v32.9: tap handling moved inside videoSection (transparent tap layer)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { handleDoubleTap() }
        )
        // 🔧 FIX CHAT SWIPE: higher minimumDistance (80) to avoid conflicts with
        // iOS edge swipe gestures (which trigger tabbar). Only horizontal swipes.
        .simultaneousGesture(
            DragGesture(minimumDistance: 80)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // Only handle clearly horizontal swipes (|h| > |v| * 2)
                    guard abs(horizontal) > abs(vertical) * 2 else { return }
                    // Свайп справа-налево (←) — открыть чат
                    if !showChatPanel && horizontal < -80 {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showChatPanel = true
                        }
                    }
                    // Свайп слева-направо (→) — закрыть чат
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

    @ViewBuilder
    private func videoSection(
        viewModel: RoomViewModel,
        videoWidth: CGFloat,
        videoHeight: CGFloat,
        isFullscreen: Bool
    ) -> some View {
        ZStack {
            // Видео контейнер
            if let mediaItem = viewModel.syncEngine.currentMediaItem,
               !mediaItem.streamURL.isEmpty {

                VideoContainerView(
                    mediaURL: mediaItem.streamURL,
                    playbackMode: mediaItem.effectivePlaybackMode,
                    isPlaying: viewModel.syncEngine.isPlaying,
                    currentTime: viewModel.syncEngine.currentTime,
                    duration: viewModel.syncEngine.duration,
                    isFullscreen: isFullscreen,
                    onTogglePlay: { viewModel.syncEngine.togglePlayPause() },
                    onSeek: { pos in viewModel.syncEngine.seek(to: pos) }
                )
            } else {
                videoPlaceholder
            }

            // 🔧 v32.9: TRANSPARENT TAP LAYER — catches taps that WKWebView
            // would otherwise swallow. When showControls=false, this layer
            // catches the tap and shows controls. When showControls=true,
            // it's disabled (allowsHitTesting=false) so taps reach the
            // ControlsOverlay buttons below.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if !showControls {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showControls = true
                        }
                        resetControlsTimer()
                    } else {
                        // Tapped on video area while controls visible —
                        // hide controls (unless tapping a button)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showControls = false
                        }
                    }
                }
                .allowsHitTesting(true)  // always catch taps on video area
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 🔧 OUR controls overlay — ALWAYS visible (YouTube controls are hidden
            // via controls=0 in embed HTML, so only Plink controls show).
            ControlsOverlay(
                isPlaying: viewModel.syncEngine.isPlaying,
                currentTime: viewModel.syncEngine.currentTime,
                duration: viewModel.syncEngine.duration,
                participantCount: viewModel.room.participantCount,
                roomName: viewModel.room.name,
                isFullscreen: isFullscreen,
                onTogglePlay: {
                    HapticManager.impact(.light)
                    viewModel.syncEngine.togglePlayPause()
                    resetControlsTimer()
                },
                onSeek: { pos in
                    viewModel.syncEngine.seek(to: pos)
                    resetControlsTimer()
                },
                onSeekRelative: { delta in
                    viewModel.syncEngine.seekRelative(delta)
                    resetControlsTimer()
                },
                onClose: {
                    if isFullscreen {
                        exitFullscreen()
                    } else {
                        Task {
                            await voiceChat?.endCall()
                            await viewModel.cleanupFlow()
                        }
                        dismiss()
                    }
                },
                onShowParticipants: {
                    showParticipants = true
                },
                onToggleFullscreen: {
                    HapticManager.impact(.light)
                    if isFullscreen {
                        exitFullscreen()
                    } else {
                        enterFullscreen()
                    }
                },
                isVisible: $showControls
            )

            // 🔧 GLASS CONTROLS: Mic, share buttons — always visible in landscape,
            // dimmed (0.35) when controls hidden, brightened (1.0) when controls visible.
            if let voiceChat {
                VStack {
                    // ── Share: правый верхний угол ──
                    HStack {
                        Spacer()
                        Button {
                            HapticManager.impact(.light)
                            shareSheetPresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.3))
                                )
                        }
                        .buttonStyle(GlassButtonStyle())
                        .opacity(showControls ? 1.0 : 0.35)
                        .padding(.trailing, 12)
                        .padding(.top, 6)
                    }

                    Spacer()

                    // ── Микрофон: левый нижний угол ──
                    HStack(spacing: 10) {
                        VoiceChatButton(voiceChat: voiceChat) {
                            voiceChat.toggleMute()
                        }
                        .opacity(showControls ? 1.0 : 0.35)
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.bottom, 6)
                }
                .animation(.easeInOut(duration: 0.25), value: showControls)
            }

            // Бегущая строка (marquee) — последнее сообщение
            MarqueeContainer(messages: syncManager?.chatMessages ?? viewModel.messages)
        }
        .frame(width: isFullscreen ? nil : videoWidth,
               height: isFullscreen ? nil : videoHeight)
        .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 16))
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

    // MARK: - Orientation Reset (фикс бага растягивания чата)

    /// Принудительный сброс в портрет — вызывается при onAppear, возврате из background,
    /// и при смене scenePhase на .active. Гарантирует что чат всегда корректного размера.
    ///
    /// 🔧 FIX v2 (July 2026): now ALSO locks the orientation at the AppDelegate
    /// level via OrientationManager.lockToPortrait(). This prevents system edge-swipe
    /// gestures and accidental device rotations from interfering with the chat layout.
    private func resetToPortrait() {
        isFullscreenMode = false
        showChatPanel = true
        showEmojiPicker = false
        OrientationManager.shared.lockToPortrait()
    }

    // MARK: - Fullscreen (YouTube-style)

    private func enterFullscreen() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isFullscreenMode = true
            showControls = true
        }
        // 🔧 FIX v2: lock to landscape at AppDelegate level so device rotation
        // events outside our control can't switch back to portrait mid-video.
        OrientationManager.shared.lockToLandscape()
        resetControlsTimer()
    }

    private func exitFullscreen() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isFullscreenMode = false
            showControls = true
        }
        // 🔧 FIX v2: lock back to portrait.
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

// MARK: - Share Sheet (UIActivityViewController wrapper)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
