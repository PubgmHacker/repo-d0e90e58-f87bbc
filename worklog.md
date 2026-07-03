# RaveClone Worklog

## Task ID: AUDIT-IOS — Native iOS Swift Code Audit

**Scope:** Full source audit of the SwiftUI iOS app at
`/home/z/my-project/raveclone-review/RaveClone/` covering networking
(WebSocket, REST, signaling), services (sync, voice, auth, media, DM,
screen capture, audio, StoreKit, friends, premium, ads), view models,
views, models, utilities, and resources.

**Method:** Line-by-line read of 50+ Swift files. Bugs categorized by
severity. Each entry lists file:line, the offending snippet, the impact,
and a concrete fix.

---

### 🔴 CRITICAL — Showstoppers / Security / Auth-Bypass

#### C1. WebSocket `isConnected` is never set to `true` — entire realtime send path is dead
- **File:** `Networking/WebSocketClient.swift:408-424`
- **What's wrong:**
  ```swift
  private func notifyConnectedIfNeeded() {
      guard !isConnected else { return }
      isConnected = true            // ← only place isConnected is set to true
      ...
      delegate?.webSocketDidConnect(self)
  }
  ```
  `notifyConnectedIfNeeded()` is declared but **never called anywhere** in
  the codebase (verified via grep). `URLSessionWebSocketTask` has no "did
  open" callback, so the comment claims to "infer open state from the
  first successful receive cycle / probe openness with a no-op send", but
  neither is implemented.
- **Impact:** `send(_:)` at line 221 checks `if isConnected` (always
  `false`) → every outgoing message is enqueued to `pendingMessages`
  and **never flushed** (flush only happens inside
  `notifyConnectedIfNeeded`). `sendHeartbeat` short-circuits at line 337.
  `delegate?.webSocketDidConnect(self)` is never invoked, so
  `RoomViewModel.connectionStatus` stays `.connecting` forever and the
  sync engine never starts. Chat, reactions, play/pause/seek,
  signaling — **none of it reaches the server**.
- **Fix:** Use `urlSession.webSocketTask(with:)`'s implicit open state by
  probing with a no-op receive right after `task.resume()`:

  ```swift
  private func connectInternal() {
      ...
      task.resume()
      socket = task
      // Probe open state by issuing an immediate receive; the first
      // successful (or first failure) callback tells us the socket is live.
      receiveMessage()
      // Also schedule a one-shot open-check
      Task { @MainActor [weak self] in
          try? await Task.sleep(nanoseconds: 250_000_000)
          self?.notifyConnectedIfNeeded()
      }
  }
  ```
  Or, more cleanly, open the socket via a `withCheckedThrowingContinuation`
  wrapper that resumes on the first receive callback.

#### C2. JWT token stored in `UserDefaults` instead of Keychain
- **File:** `Services/AuthService.swift:130-131`
- **What's wrong:**
  ```swift
  defaults.set(token, forKey: Keys.authToken)
  defaults.set(expiry, forKey: Keys.tokenExpiry)
  ```
  Also `Keys.savedUser` at line 32-33 stores the full `User` JSON in
  UserDefaults. JWTs in `UserDefaults` are readable by anyone with
  filesystem access (including sandbox escapes, iCloud backup extraction,
  and on jailbroken devices).
- **Impact:** Credential disclosure → session hijack → full account
  takeover. Apple App Review will reject for not following iOS Secure
  Coding guidelines for credentials.
- **Fix:** Use the existing `KeychainHelper` (already defined in
  `YandexAuthService.swift:238`) — note that the Yandex path already
  stores its JWT in Keychain while the main auth path uses UserDefaults,
  an inconsistent and unsafe split:

  ```swift
  private func cacheToken(_ token: String, expiry: TimeInterval) async {
      authToken = token
      tokenExpiry = expiry
      api.authToken = token
      KeychainHelper.shared.save(token, for: Keys.authToken)
      KeychainHelper.shared.save(String(expiry), for: Keys.tokenExpiry)
  }
  ```

#### C3. `AuthService.getFreshToken()` never actually refreshes
- **File:** `Services/AuthService.swift:118-124`
- **What's wrong:**
  ```swift
  func getFreshToken() async -> String? {
      let now = Date().timeIntervalSince1970
      if authToken == nil || now >= tokenExpiry - 300 {
          return authToken        // ← same value as the else branch
      }
      return authToken            // ← identical
  }
  ```
  Both branches return the existing (potentially expired) `authToken`.
  There is no refresh-token call to `/api/auth/refresh` or similar.
- **Impact:** Once the 24h JWT expires, the app silently keeps sending
  expired tokens. Server returns 401; user is logged out without warning
  or any in-app recovery path. The `bridgeAuthToken()` call in
  `RaveCloneApp.init` then propagates an expired token to WebSocketClient
  and MediaService.
- **Fix:**
  ```swift
  func getFreshToken() async -> String? {
      guard let token = authToken else { return nil }
      let now = Date().timeIntervalSince1970
      // Refresh if within 5 min of expiry (or past it)
      if now >= tokenExpiry - 300 {
          return await refreshJWT() ?? token
      }
      return token
  }
  private func refreshJWT() async -> String? { /* POST /auth/refresh */ }
  ```

#### C4. `DMChatService` constructs its own `APIClient` with no auth token
- **File:** `Services/DMChatService.swift:16`
- **What's wrong:**
  ```swift
  private let api = APIClient()
  ```
  A fresh `APIClient` is created per `DMChatService` instance. Its
  `authToken` is `nil` and is never assigned by anyone. The
  `loadHistory(friendId:)` guard at line 28 (`guard api.authToken != nil
  else { return }`) silently bails; `sendMessage` will get a 401.
- **Impact:** DM feature is completely non-functional. All DM API calls
  fail with 401. The UI shows stale optimistic messages but they never
  reach the server, and history never loads.
- **Fix:** Inject the shared `APIClient` (the same instance
  `RaveCloneApp.init` gives to `AuthService`) into `DMChatService`:

  ```swift
  @MainActor
  final class DMChatService: ObservableObject {
      private let api: APIClient
      init(api: APIClient) { self.api = api }
      ...
  }
  ```

#### C5. `FriendManager` constructs its own `APIClient` with no auth token
- **File:** `Services/FriendManager.swift:26`
- **What's wrong:** Same as C4 — `private let api = APIClient()`. Every
  `loadFriends` / `loadRequests` / `sendRequest` / `acceptRequest` /
  `searchUsers` call uses an unauthenticated client.
- **Impact:** Entire social layer (friends, requests, search) is broken —
  every API call returns 401. `loadAll()` in `init()` silently no-ops
  because of the `guard api.authToken != nil` checks.
- **Fix:** Same as C4 — inject the shared authenticated `APIClient`.

#### C6. `AdminPanelView` constructs its own `APIClient` with no auth token
- **File:** `Views/Admin/AdminPanelView.swift:8`
- **What's wrong:** `private let api = APIClient()` — same pattern.
  `loadUsers` calls `api.request("admin/users")` which always 401s.
- **Impact:** Admin panel cannot load or modify any data. The view
  silently shows empty state forever; ban/unban/delete actions fail.
- **Fix:** Inject the shared authenticated `APIClient` from the app
  container.

#### C7. `RoomView.setupViewModel()` hardcodes `currentUserId: "current_user"`
- **File:** `Views/Room/RoomView.swift:470-493`
- **What's wrong:**
  ```swift
  let syncEngine = SyncEngine(
      wsClient: wsClient,
      roomID: room.id,
      userID: "current_user",                       // ← hardcoded
      isHost: room.hostID == "current_user"          // ← always false
  )
  let vm = RoomViewModel(
      room: room,
      currentUserId: "current_user",                 // ← hardcoded
      ...
  )
  ```
- **Impact:** `RoomViewModel.isHost` is `room.hostID == "current_user"`
  → always `false` for real users whose hostID is a UUID from the
  server. SyncEngine's `play()`/`pause()`/`seek()` all `guard isHost`
  and silently no-op. State broadcast timer is never started. Host's
  local sync commands are never sent. The "saved position" restore at
  line 88 (`viewModel.syncEngine.seek(to: savedPosition)`) is also
  gated on `isHost` and silently dropped.
- **Fix:** Resolve the real user id from `AuthService.currentUser?.id`
  and pass it down. The whole `setupViewModel` should be removed in
  favor of dependency injection from `RaveCloneApp`:

  ```swift
  // In RaveCloneApp
  .navigationDestination(item: $navigateToRoom) { room in
      RoomView(room: room,
               currentUserId: authService.currentUser?.id ?? "",
               apiClient: apiClient,
               authService: authService,
               wsClient: wsClient,
               roomService: roomService)
  }
  ```

#### C8. `RoomCreationView.createRoom()` hardcodes `hostID: "current_user"` and `hostIsPremium: false`
- **File:** `Views/Home/RoomCreationView.swift:469-483`
- **What's wrong:**
  ```swift
  let room = Room(
      ...
      hostID: "current_user",          // ← hardcoded
      hostName: "You",
      ...
      hostIsPremium: false,            // ← hardcoded
      ...
  )
  ```
  Also in `CreateRoomView.swift:325-337`.
- **Impact:** Even if the actual user is premium, `hostIsPremium=false`
  is sent to participants → AdSessionManager will treat this host as
  non-premium and serve ads. `hostID="current_user"` means `isHost`
  checks elsewhere never match. (The room JSON sent to the server
  includes these bogus values too, though the server presumably
  overrides hostID — but `hostIsPremium` would still be wrong if the
  server trusts the client.)
- **Fix:**
  ```swift
  let me = await authService.currentUser()
  let room = Room(
      ...
      hostID: me?.id ?? UUID().uuidString,
      hostName: me?.username ?? "You",
      ...
      hostIsPremium: PremiumStatusManager.shared.isPremium,
      ...
  )
  ```

#### C9. `PremiumStatusManager.setPremium(_:)` allows manual premium activation without IAP
- **File:** `Services/PremiumStatusManager.swift:62-72`
- **What's wrong:**
  ```swift
  func setPremium(_ active: Bool) {
      if active {
          isPremium = true
          subscriptionExpiry = Calendar.current.date(byAdding: .day, value: 30, to: Date())
      }
      ...
  }
  ```
  `isPremium` is persisted in `UserDefaults` (line 105). Any caller (or
  user with filesystem access) can flip the `rave_user_is_premium` flag
  in defaults to gain premium features forever — bypassing StoreKit,
  bypassing server validation, bypassing ad gating, raising participant
  caps from 4 to 50.
- **Impact:** Total IAP bypass. Premium features (4K, no-ads, 50
  participants, custom nick/avatar, room themes) are all unlocked by
  toggling a single `Bool` in `UserDefaults`. This is a guaranteed App
  Review rejection (Guideline 3.1.1 — IAP required for digital goods).
- **Fix:** Delete `setPremium`. Premium must only be activated through
  `StoreManager.handleSuccessfulPurchase` AND validated server-side:

  ```swift
  // Delete setPremium entirely.
  // In StoreManager.handleSuccessfulPurchase, POST the StoreKit
  // transaction JWS to /api/iap/verify and let the server set
  // isPremium on the User record. PremiumStatusManager should read
  // from User.isPremium (returned by /api/auth/me), not from defaults.
  ```

#### C10. `AdSessionManager.triggerAd()` skips the premium-host check
- **File:** `Services/AdSessionManager.swift:122-136`
- **What's wrong:**
  ```swift
  private func triggerAd() {
      guard !isAdPlaying else { return }
      isAdPlaying = true
      nextAdCountdown = 0
      onBroadcastAdCommand?(.play)
      onAdShouldPlay?()
      ...
  }
  ```
  The premium-bypass check (`shouldPlayAd(hostIsPremium:)` at line 109)
  is never invoked from `triggerAd`. It's a separate method that callers
  must remember to call — but nothing does.
- **Impact:** Even premium hosts see ads, defeating the entire "Premium
  = no ads" value proposition. Combined with C8 (hostIsPremium always
  false), every host sees ads regardless of subscription.
- **Fix:** Call the check at the top of `triggerAd`:
  ```swift
  private func triggerAd() {
      guard !isAdPlaying else { return }
      guard shouldPlayAd(hostIsPremium: PremiumStatusManager.shared.isPremium) else {
          // Premium host: restart timer for next interval, no ad shown.
          startAdTimer()
          return
      }
      isAdPlaying = true
      ...
  }
  ```

#### C11. `DirectMessage.isOwnMessage` checks the wrong sentinel
- **File:** `Models/DirectMessage.swift:19-21`
- **What's wrong:**
  ```swift
  var isOwnMessage: Bool {
      senderID == "current_user"
  }
  ```
  But `DMChatService.sendMessage` (line 69-82) sets `senderID = me`
  where `me = currentUserId ?? "me"` — and `currentUserId` reads the
  real user id from `UserDefaults["rave_saved_user"]`. So own messages
  have `senderID` equal to the real user UUID, NOT `"current_user"`.
  The check returns `false` for own messages.
- **Impact:** In DMChatView, your own sent messages render on the LEFT
  (as if from the other person) with their avatar placeholder. The
  premium shimmer (line 219) never triggers for own messages.
- **Fix:** Either thread the real current user id into the model at
  construction time, or compare to the cached user id:
  ```swift
  var isOwnMessage: Bool {
      let me = UserDefaults.standard.data(forKey: "rave_saved_user")
          .flatMap { try? JSONDecoder().decode(User.self, from: $0) }?.id
      return senderID == me
  }
  ```
  Better: pass `currentUserId` into `DMChatView` and compare there.

#### C12. Missing Info.plist privacy usage descriptions
- **File:** `Resources/Info.plist`
- **What's wrong:** No `NSMicrophoneUsageDescription`, no
  `NSCameraUsageDescription`, no `NSPhotoLibraryUsageDescription`,
  no `NSLocalNetworkUsageDescription`. The app has voice chat
  (`VoiceChatService`), screen capture (`ScreenCaptureService`), and
  avatar upload (`ProfileViewModel.saveAvatar`) — all of which require
  these keys.
- **Impact:** `AVAudioSession.requestRecordPermission` and
  `AVCaptureSession.startRunning` will crash the app with
  `EXC_BREAKPOINT` on first invocation. App Store submission will be
  auto-rejected.
- **Fix:** Add to Info.plist:
  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>Микрофон используется для голосового общения в комнате</string>
  <key>NSCameraUsageDescription</key>
  <string>Камера нужна для аватара и стриминга</string>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>Доступ к галерее нужен для выбора аватара</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Локальная сеть используется для WebRTC-соединения</string>
  ```

#### C13. Empty entitlements file — no Associated Domains, no IAP, no APNs
- **File:** `Resources/Plink.entitlements`
- **What's wrong:** The file is an empty `<dict/>`. No
  `com.apple.developer.associated-domains` (Universal Links won't work
  — `DeepLinkRouter` is dead on real devices), no
  `com.apple.developer.in-app-payments` (StoreKit 2 subscriptions will
  silently fail in production), no
  `com.apple.developer.pushnotifications.unrestricted` (FCM tokens
  registered in AuthService.registerFCMToken will be useless).
- **Impact:** Universal Links, IAP, and push notifications all silently
  fail in release builds. The deep-link share flow (`ShareManager`,
  `DeepLinkRouter`) returns 404 on tap. Premium subscriptions can be
  initiated but cannot complete verification server-side.
- **Fix:** Add entitlements:
  ```xml
  <key>com.apple.developer.associated-domains</key>
  <array>
      <string>applinks:raveclone.app</string>
  </array>
  <key>com.apple.developer.in-app-payments</key>
  <array>
      <string>merchant.com.syncwatch.raveclone</string>
  </array>
  <key>aps-environment</key>
  <string>production</string>
  ```

#### C14. Yandex OAuth `clientID` is a hardcoded placeholder
- **File:** `Services/YandexAuthService.swift:40-41`
- **What's wrong:**
  ```swift
  clientID: String = "yandex_client_id_placeholder",
  ```
  The default clientID is a placeholder string. Any code path that
  instantiates `YandexAuthService()` without overriding it (which is
  every callsite we can see — the type is not even instantiated from
  `RaveCloneApp`) will hit Yandex's OAuth endpoint with a non-existent
  client_id, which Yandex will reject with `400 invalid_client`.
- **Impact:** Yandex ID sign-in is non-functional. Yandex Plus
  subscription detection (`isPlus`) never runs.
- **Fix:** Move the real clientID into a build configuration / xcconfig
  file referenced from `Info.plist`, then read via
  `Bundle.main.object(forInfoDictionaryKey: "YANDEX_CLIENT_ID")`.

---

### 🟠 HIGH — Leaks / Crashes / Resource Lifecycle

#### H1. `WebSocketClient.scheduleReconnect` can leave `isReconnecting` stuck
- **File:** `Networking/WebSocketClient.swift:390-401`
- **What's wrong:**
  ```swift
  private func scheduleReconnect() {
      guard !isManuallyDisconnected else { return }
      let delay = nextBackoffDelay()
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
          guard let self, !self.isManuallyDisconnected else { return }
          self.isReconnecting = false
          self.connectInternal()
      }
  }
  ```
  If the user calls `disconnect()` during the backoff window,
  `isManuallyDisconnected` becomes `true`, the asyncAfter closure bails
  early — but `isReconnecting` stays `true` (it's only reset to `false`
  inside the closure's success branch). Combined with `handleDisconnect`'s
  guard at line 378 (`guard !isReconnecting`), subsequent real
  disconnects will be silently dropped, breaking the next reconnect
  cycle.
- **Impact:** After backgrounding + manual disconnect, the client may
  refuse to ever reconnect.
- **Fix:** Reset `isReconnecting` in `disconnect()`:
  ```swift
  func disconnect() {
      ...
      isReconnecting = false
      ...
  }
  ```

#### H2. `RoomViewModel` and `RoomSyncManager` race for `wsClient.delegate`
- **File:** `Views/Room/RoomView.swift:489` and `Services/RoomSyncManager.swift:101`
- **What's wrong:**
  ```swift
  // RoomViewModel.joinRoomFlow (line 89)
  wsClient.delegate = self

  // RoomView.setupViewModel (line 506) calls manager.connect()
  // RoomSyncManager.connect (line 101)
  wsClient.delegate = self
  ```
  Both objects try to become the WebSocket delegate. The last assignment
  wins. `setupViewModel` runs first (via `.onAppear` at line 70) and
  calls `manager.connect()`, so `RoomSyncManager` becomes the delegate.
  Then `joinRoomFlow` (in `.task`) reassigns to `RoomViewModel`.
  Messages arriving between these two assignments go to the wrong
  handler.
- **Impact:** Race condition. Inbound WS messages may be routed to
  RoomSyncManager (whose `handleRawMessage` decodes via different
  envelope types) instead of RoomViewModel (whose `routeInbound` also
  drives `syncEngine.handleSyncMessage`). Two delegates with divergent
  routing logic.
- **Fix:** Use a single delegate (probably RoomViewModel) and have it
  forward to RoomSyncManager explicitly, or refactor to a multicast
  delegate pattern.

#### H3. `VideoContainerView` creates a SECOND `AVPlayer` separate from SyncEngine's
- **File:** `Views/Room/VideoContainerView.swift:114-146`
- **What's wrong:**
  ```swift
  final class PlayerUIView: UIView {
      ...
      init(url: URL, isPlaying: Bool, currentTime: TimeInterval) {
          super.init(frame: .zero)
          let item = AVPlayerItem(url: url)
          ...
          let p = AVPlayer(playerItem: item)
          ...
          player = p
      }
  }
  ```
  `SyncEngine.loadMedia` (Services/SyncEngine.swift:125) ALSO creates an
  `AVPlayer` from the same URL. The `PlayerUIView` instance creates
  another one. **Two AVPlayers play the same stream independently** —
  the SyncEngine's player is invisible (no `AVPlayerLayer` attached);
  the `PlayerUIView`'s player is visible but doesn't honor sync commands
  directly.
- **Impact:** SyncEngine controls one AVPlayer (invisible); the user
  sees a different AVPlayer (out of sync). Every play/pause/seek the
  SyncEngine applies to its hidden player must be re-applied via
  `updateUIView` to the visible player, with a 1.5s tolerance check
  that fights the sync engine's own time observer. Visual desync is
  guaranteed. CPU/memory wasted on duplicate decoding.
- **Fix:** Render the SyncEngine's AVPlayer via a single
  `AVPlayerLayer` exposed from SyncEngine:
  ```swift
  // SyncEngine
  var playerLayer: AVPlayerLayer { ... }

  // VideoContainerView
  struct VideoContainerView: View {
      let playerLayer: AVPlayerLayer
      var body: some View {
          AVPlayerLayerView(layer: playerLayer)
      }
  }
  ```

#### H4. `AdSessionManager.deinit` doesn't invalidate timers
- **File:** `Services/AdSessionManager.swift:66-68`
- **What's wrong:**
  ```swift
  deinit {
      // Cannot touch @MainActor state in deinit; timers invalidate themselves.
  }
  ```
  Comment is wrong. `Timer.scheduledTimer` retains its target/closure
  via the current run loop. The closure captures `self` weakly
  (`Task { @MainActor [weak self] in ... }`), but the `Timer` itself
  is held by the run loop until invalidated. The `Timer` then retains
  the closure, the closure retains `Task`, etc.
- **Impact:** `AdSessionManager` instances leak until `stopAllTimers()`
  is explicitly called. If a room is dismissed without calling
  `stopAllTimers`, the timer keeps firing (and its `Task` blocks keep
  the manager alive), causing phantom ad triggers in dead rooms.
- **Fix:** Invalidate in a `nonisolated deinit`:
  ```swift
  nonisolated deinit {
      adTimer?.invalidate()
      countdownTimer?.invalidate()
  }
  ```
  `Timer.invalidate()` is thread-safe enough for deinit teardown.

#### H5. `AdPlayerView.startCountdown` Timer not cleaned up on dismiss
- **File:** `Views/Room/AdPlayerView.swift:73-88`
- **What's wrong:** `Timer.scheduledTimer(withTimeInterval: 1, repeats:
  true) { timer in ... }` is created in `startCountdown()`, called from
  `.onAppear`. The timer is invalidated only when `countdown <= 0`. If
  the view is dismissed before the 15s countdown completes, the timer
  keeps firing — calling `onDismiss()` on a stale view.
- **Impact:** After dismissing the ad early, `onDismiss` is invoked ~15
  times over the next 15s, each potentially triggering the host's
  `AdSessionManager.finishAd()` and restarting the ad cycle.
- **Fix:** Store the timer in `@State` and invalidate in `onDisappear`:
  ```swift
  @State private var countdownTimer: Timer?
  ...
  .onDisappear { countdownTimer?.invalidate() }
  ```

#### H6. `AudioManager.animateVolume` spawns 10 racing Tasks
- **File:** `Services/AudioManager.swift:103-122`
- **What's wrong:**
  ```swift
  private func animateVolume(to target: Float, duration: TimeInterval) {
      ...
      for step in 1...steps {
          Task { @MainActor [weak self, weak player] in
              try? await Task.sleep(...)
              ...
              player.volume = startVolume + delta * progress
              self?.currentVolume = player.volume
          }
      }
  }
  ```
  Each call schedules 10 detached Tasks. If `animateVolume` is called
  twice in quick succession (e.g., user mutes → unmutes within 300ms),
  20 tasks overlap, each writing `player.volume` with stale `delta`
  values. Final volume is unpredictable.
- **Impact:** Audio ducking/un-ducking glitches; volume may settle on
  wrong value. Wakes CPU 10x per 300ms transition.
- **Fix:** Cancel prior animation Task before starting a new one:
  ```swift
  private var volumeAnimTask: Task<Void, Never>?
  private func animateVolume(to target: Float, duration: TimeInterval) {
      volumeAnimTask?.cancel()
      volumeAnimTask = Task { @MainActor [weak self, weak player] in
          guard let player else { return }
          for step in 1...10 {
              try? await Task.sleep(...)
              if Task.isCancelled { return }
              player.volume = ...
              self?.currentVolume = player.volume
          }
      }
  }
  ```

#### H7. `AmbilightSampler.processFrame` passes CVPixelBuffer to a detached Task without retaining
- **File:** `Views/Room/AmbilightBackground.swift:79-84`
- **What's wrong:**
  ```swift
  Task.detached(priority: .utility) { [ciContext] in
      let extracted = await Self.extractDominantColors(from: pixelBuffer, context: ciContext)
      ...
  }
  ```
  `pixelBuffer` is a `CVPixelBuffer` — a CoreFoundation object. Swift
  bridges it as an unretained reference. When `Task.detached` captures
  it, Swift doesn't call `CVPixelBufferRetain`. If the source
  `AVPlayerItemVideoOutput` recycles the buffer before the detached task
  runs (likely, since the display link fires at 60Hz and the task is
  throttled to 2Hz), the buffer is invalidated and `CIImage(cvPixelBuffer:)`
  reads freed memory.
- **Impact:** Use-after-free. Likely intermittent crashes in
  `extractDominantColors` under memory pressure or on slow devices.
- **Fix:** Retain manually:
  ```swift
  Task.detached(priority: .utility) { [ciContext] in
      CVPixelBufferRetain(pixelBuffer)
      defer { CVPixelBufferRelease(pixelBuffer) }
      let extracted = await Self.extractDominantColors(from: pixelBuffer, context: ciContext)
      ...
  }
  ```

#### H8. `PlayerUIView`'s `CADisplayLink` retains `self` forever if `deinit` doesn't fire
- **File:** `Views/Room/VideoContainerView.swift:157-193`
- **What's wrong:** `CADisplayLink(target: self, selector: ...)` retains
  its target. `deinit { displayLink?.invalidate() }` correctly releases,
  but `deinit` only fires when no one holds `PlayerUIView`. SwiftUI's
  `UIViewRepresentable` tears down the `UIView` when the parent view
  body re-evaluates without it. If the parent view stays alive but the
  `mediaURL` changes, `makeUIView` is called again creating a new
  `PlayerUIView` while the old one's display link is still firing
  against an orphaned player.
- **Impact:** Display link leaks across URL changes; each new media
  load adds another 4Hz capture callback. After 10 media changes, 10
  display links call `AmbilightSampler.shared.processFrame` per frame.
- **Fix:** Add a `willMove(toSuperview:)` override that invalidates:
  ```swift
  override func willMove(toSuperview newSuperview: UIView?) {
      if newSuperview == nil {
          displayLink?.invalidate()
          displayLink = nil
          player?.pause()
      }
  }
  ```

#### H9. `RoomView.setupViewModel` creates fresh service instances on every appear
- **File:** `Views/Room/RoomView.swift:469-511`
- **What's wrong:**
  ```swift
  private func setupViewModel() {
      let api = APIClient()              // ← new, no auth token
      let wsClient = WebSocketClient()   // ← new socket
      let roomService = RoomService(api: api)
      let authService = AuthService(api: api)
      ...
  }
  ```
  Each time `RoomView` is presented, a brand-new `APIClient`,
  `WebSocketClient`, `AuthService` (which re-reads `UserDefaults` and
  restores the user), `SignalingClient`, `VoiceChatService`,
  `SyncEngine`, `RoomViewModel`, and `RoomSyncManager` are created.
  None are reused from `RaveCloneApp`. The new `APIClient` has no auth
  token. The new `WebSocketClient` has no JWT.
- **Impact:** Every room entry starts an unauthenticated session. The
  user's saved JWT in `AuthService` (from app launch) is never
  propagated. Room creation, joining, sync — all 401. Plus: when the
  view dismisses, all those services are deallocated, but the
  `manager.connect()` closures capture `vm` strongly (line 497-504),
  keeping the entire graph alive until the WebSocket times out.
- **Fix:** Inject services from the app container via `EnvironmentValue`
  or constructor param.

#### H10. `APIClient.encoder/decoder` are mutable shared state on a `Sendable` class
- **File:** `Networking/APIClient.swift:5-18`
- **What's wrong:** `APIClient` is declared `Sendable`, but its
  `JSONEncoder` and `JSONDecoder` are stored `let` properties.
  `JSONEncoder` and `JSONDecoder` are **not thread-safe** (they
  configure internal state during encode/decode). Concurrent
  `request(...)` calls from multiple `Task`s share these instances.
- **Impact:** Random decoding failures, corrupted request bodies, or
  crashes (EXC_BAD_ACCESS) under load. Hard to reproduce.
- **Fix:** Either mark them `nonisolated(unsafe)` and document, or
  create a fresh encoder/decoder per request, or constrain `APIClient`
  to a single actor:
  ```swift
  actor APIClient {
      private let encoder = JSONEncoder()
      private let decoder = JSONDecoder()
      ...
  }
  ```

#### H11. `APIClient.request<T>` cannot handle 204 No Content
- **File:** `Networking/APIClient.swift:62-64`
- **What's wrong:**
  ```swift
  case 200..<300:
      return try decoder.decode(T.self, from: data)
  ```
  Many REST endpoints return `204 No Content` with an empty body.
  `JSONDecoder.decode([], from: Data())` throws. Generic `request<T>`
  on a 204 response throws a decoding error rather than succeeding.
- **Impact:** `requestNoBody` exists as a workaround, but any caller
  that accidentally uses `request<EmptyResponse>` against a 204 endpoint
  gets a confusing decoding error.
- **Fix:** If `T == EmptyResponse` or `data.isEmpty`, return a default:
  ```swift
  case 200..<300:
      if data.isEmpty, let empty = T.self as? EmptyDecodable.Type {
          return empty.empty() as! T
      }
      return try decoder.decode(T.self, from: data)
  ```

#### H12. `WebSocketClient` `nonisolated(unsafe) var socket` accessed from multiple isolation contexts
- **File:** `Networking/WebSocketClient.swift:53`
- **What's wrong:**
  ```swift
  private nonisolated(unsafe) var socket: URLSessionWebSocketTask?
  ```
  Accessed from: `connectInternal` (@MainActor), `disconnect`
  (@MainActor), `cancelSocketForDeinit` (nonisolated), `sendRaw`
  (closure on background queue). The `nonisolated(unsafe)` annotation
  silences the compiler but doesn't provide actual synchronization.
- **Impact:** Data race on `socket?.cancel()` and `socket = nil` if a
  reconnect fires during `deinit` from a background queue. Crashes
  possible under TSan.
- **Fix:** Wrap in a lock or actor:
  ```swift
  private let socketLock = NSLock()
  private var _socket: URLSessionWebSocketTask?
  private var socket: URLSessionWebSocketTask? {
      get { socketLock.lock(); defer { socketLock.unlock() }; return _socket }
      set { socketLock.lock(); defer { socketLock.unlock() }; _socket = newValue }
  }
  ```

#### H13. `RoomViewModel.messages` is unbounded — long rooms leak memory
- **File:** `ViewModels/RoomViewModel.swift:13` and `Views/Room/RoomView.swift:158-167`
- **What's wrong:**
  ```swift
  var messages: [ChatMessage] = []
  ```
  Every inbound chat message is appended. There's no upper bound.
  `RoomSyncManager` has `maxChatMessages = 200`, but `RoomViewModel`
  maintains its own `messages` array (used directly by `RoomChatView`
  when `syncManager?.chatMessages` is nil, AND populated by
  `routeInbound` line 233-235).
- **Impact:** In a 6-hour room with active chat, the array grows to
  tens of thousands of `ChatMessage` structs, each holding a `Date`,
  `String`, optional URL — roughly 200 bytes each → 10+ MB of dead
  history kept alive. SwiftUI `LazyVStack` re-renders on every append.
- **Fix:** Cap at 200 like RoomSyncManager:
  ```swift
  private let maxMessages = 200
  ...
  messages.append(chatMsg)
  if messages.count > maxMessages { messages.removeFirst(messages.count - maxMessages) }
  ```

#### H14. `AuthService.init` mutates `currentUser` from a detached `Task`
- **File:** `Services/AuthService.swift:32-35`
- **What's wrong:**
  ```swift
  if let data = defaults.data(forKey: Keys.savedUser),
     let user = try? JSONDecoder().decode(User.self, from: data) {
      Task { @MainActor in self.currentUser = user }
  }
  ```
  `AuthService` is not `@MainActor` (only `currentUser` is annotated
  `@MainActor private(set) var`). The init is non-isolated; spawning a
  `Task { @MainActor in self.currentUser = user }` is the only safe
  path. But `RaveCloneApp.checkAuth` calls `authService.currentUser()`
  immediately after init, racing against this detached task.
- **Impact:** Cold launch: `currentUser()` returns nil because the
  restore task hasn't run yet. `isSignedIn = false`, splash disappears
  to LoginView, then 200ms later `currentUser` populates — user sees a
  flash of login screen on every cold launch with valid session.
- **Fix:** Make `AuthService` `@MainActor` entirely, or restore
  synchronously in init by gating `currentUser` on a `Mutex`/actor.

---

### 🟡 MEDIUM — Race Conditions / State Machine / @MainActor Violations

#### M1. `SyncEngine.handleSeek` extrapolation may jump backwards on real seeks
- **File:** `Services/SyncEngine.swift:389-417`
- **What's wrong:** `isStatePulse = elapsedSinceEvent < stateBroadcastInterval + 1`
  is a heuristic that treats any seek arriving within 3s of broadcast as a
  state pulse. But the host's periodic state broadcast (every 2s) and a
  user-initiated seek command can both fall within that 3s window. When
  a real seek arrives shortly after a state pulse, the receiver
  extrapolates forward by `elapsedSinceEvent` (which is small), landing
  near the original position — NOT the user's intended seek target.
- **Impact:** Real seeks by the host get silently reverted. UI shows
  the seek happening then snapping back.
- **Fix:** Add a distinct `command` value for state pulses vs explicit
  seeks (e.g., reuse `.stateResponse`), or include an
  `isStatePulse: Bool` field in `SyncMessage`.

#### M2. `SignalingMessage.decode` uses string substring to detect payload type
- **File:** `Networking/SignalingMessage.swift:43-47`
- **What's wrong:**
  ```swift
  public static func decode(from raw: String) -> SignalingMessage? {
      guard raw.contains("\"kind\"") else { return nil }
      ...
  }
  ```
  Any chat message whose text happens to contain the literal
  `"kind"` substring (e.g., a user typing `the "kind" of movie`) will
  pass the guard and be attempted as a `SignalingMessage` decode. If
  the JSON structure also happens to match, the message is consumed by
  the signaling layer.
- **Impact:** Occasional swallowed chat messages. Brittle.
- **Fix:** Use a dedicated `type` field for routing, or decode with
  `JSONDecoder` and check for `kind` after.

#### M3. `RoomViewModel.routeInbound` decodes every message up to 4 times
- **File:** `ViewModels/RoomViewModel.swift:217-250`
- **What's wrong:**
  ```swift
  if let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: data) { ... }
  if voiceChat.ingest(raw: raw) { ... }
  if let chatMsg = try? JSONDecoder().decode(ChatMessage.self, from: data) { ... }
  if let payload = try? JSONDecoder().decode(ParticipantUpdate.self, from: data) { ... }
  ```
  Each inbound WS message triggers up to 4 JSON decode attempts. Worse,
  `SyncMessage` has `command: SyncCommand` and `roomID: String` as
  required fields — if a chat payload happens to also have those keys
  (or names overlap), it'll succeed on the wrong decoder.
- **Impact:** CPU waste on hot path; mis-routing risk.
- **Fix:** Peek at a single `type` field once and dispatch:
  ```swift
  guard let type = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String else { return }
  switch type { case "chat": ...; case "sync": ...; case "participant_joined": ... }
  ```

#### M4. `RoomSyncManager.handleRawMessage` decodes every message up to 4 times
- **File:** `Services/RoomSyncManager.swift:195-221`
- **What's wrong:** Same pattern as M3 — WSPingPong, AdCommandPayload,
  SyncMessage, RoomEventEnvelope, all attempted in sequence.
- **Impact:** Same as M3.
- **Fix:** Same as M3.

#### M5. `StoreManager.restorePurchases` doesn't actually restore
- **File:** `Services/StoreManager.swift:115-126`
- **What's wrong:**
  ```swift
  func restorePurchases() async {
      purchaseState = .restoring
      ...
      try await AppStore.sync()
      purchaseState = .idle
  }
  ```
  `AppStore.sync()` only re-syncs the StoreKit transaction cache with
  Apple's servers. It does NOT iterate `Transaction.currentEntitlements`
  to verify active subscriptions and apply them locally. After a
  successful `sync()`, if the user has an active subscription that was
  previously finished (via `transaction.finish()`), no callback fires
  and `PremiumStatusManager.isPremium` stays `false`.
- **Impact:** Users reinstalling the app on a new device tap "Restore
  Purchases" → silently nothing happens → they think their subscription
  is lost. App Review rejects for not providing working restore.
- **Fix:**
  ```swift
  func restorePurchases() async {
      purchaseState = .restoring
      try? await AppStore.sync()
      for await result in Transaction.currentEntitlements {
          guard let t = try? Self.checkVerified(result) else { continue }
          await handleSuccessfulPurchase(t)
      }
      purchaseState = .idle
  }
  ```

#### M6. `PremiumStatusManager.isPremium` loaded from `UserDefaults` on every launch
- **File:** `Services/PremiumStatusManager.swift:112-133`
- **What's wrong:** `loadPersistedState` reads `rave_user_is_premium`
  from `UserDefaults` and trusts it. Combined with C9 (`setPremium(true)`
  is callable by anyone), the local premium state is fully attacker
  controlled.
- **Impact:** Premium bypass persists across launches. Even if IAP is
  added correctly, the local state can diverge from server state.
- **Fix:** Source of truth must be the server's `User.isPremium` field
  (from `/api/auth/me`). Local `UserDefaults` cache should be a hint,
  never authoritative. On each app launch, fetch user from server and
  reconcile.

#### M7. `APIClient.requestNoBody` missing 404 handling
- **File:** `Networking/APIClient.swift:124-131`
- **What's wrong:** `request<T>` has explicit `case 404: throw
  .notFound`, but `requestNoBody` only handles `401` and a generic
  `default`. Callers of `requestNoBody` (e.g., `leaveRoom`,
  `deleteRoom`, `removeFriend`) cannot distinguish "not found" from
  "server error".
- **Impact:** `leaveRoom` errors when room already deleted show
  "Ошибка сервера (404): Request failed" instead of "Комната не найдена".
- **Fix:** Mirror the `request<T>` switch.

#### M8. `Room.isHost` always returns `false` (dead computed property)
- **File:** `Models/Room.swift:25-28`
- **What's wrong:**
  ```swift
  var isHost: Bool {
      // Set at runtime by ViewModel based on current user
      false
  }
  ```
  Comment lies — no code path sets this. Anyone consuming `room.isHost`
  will always get `false`.
- **Impact:** Dead/misleading code; potential silent failure if used.
- **Fix:** Delete the property or implement it with an injected user ID:
  ```swift
  func isHost(userId: String) -> Bool { hostID == userId }
  ```

#### M9. `OrientationManager.isPortrait` has wrong operator-precedence logic
- **File:** `Utilities/OrientationManager.swift:38-48`
- **What's wrong:**
  ```swift
  var isPortrait: Bool {
      UIDevice.current.orientation.isPortrait ||
      (UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .first?
          .interfaceOrientation.isPortrait ?? true &&
       (UIDevice.current.orientation == .unknown || ...))
  }
  ```
  `??` has lower precedence than `&&`. So the right operand parses as
  `compactMap.first?.interfaceOrientation.isPortrait ?? (true && (...))`
  — meaning if `interfaceOrientation.isPortrait` is `false` (landscape),
  the `??` falls through to `true && (...)`, possibly returning `true`
  for landscape orientations when `UIDevice.current.orientation ==
  .unknown`.
- **Impact:** RoomView's landscape detection (which uses geometry, not
  this) is fine, but any consumer of `OrientationManager.isPortrait`
  gets wrong answers in mixed states (device flat on table + landscape
  app).
- **Fix:** Add explicit parens:
  ```swift
  (first?.interfaceOrientation.isPortrait ?? true) &&
  (UIDevice.current.orientation == .unknown || ...)
  ```

#### M10. `RoomView` calls `voiceChat.startCall` twice
- **File:** `Views/Room/RoomView.swift:79-90`
- **What's wrong:**
  ```swift
  .task {
      guard let viewModel else { return }
      await viewModel.joinRoomFlow()           // ← calls voiceChat.startCall
      try? await voiceChat?.startCall(roomId: room.id)  // ← calls it AGAIN
      ...
  }
  ```
  `joinRoomFlow` already calls `try await voiceChat.startCall(roomId:
  room.id)` at line 97. The `.task` block calls it again at line 83.
  `VoiceChatService.startCall` has `guard !isActive else { return }`,
  so it's idempotent — but the second call's `try?` swallows any
  legitimate error from the first call's setup.
- **Impact:** Wasted work; potential state confusion if the first call
  failed mid-setup and the second succeeds.
- **Fix:** Remove the redundant call at line 83.

#### M11. `WebSocketClient.handleReceiveResult` recursively re-arms `receiveMessage` on main actor
- **File:** `Networking/WebSocketClient.swift:286-293`
- **What's wrong:** On `.success`, `receiveMessage()` is called again,
  which calls `socket?.receive { ... Task { @MainActor in
  handleReceiveResult } }`. Each receive hop is one full main-actor
  cycle. A burst of 100 messages from the server serializes through
  100 main-actor hops, blocking UI.
- **Impact:** UI stutter during chat floods or initial room state dump.
- **Fix:** Process messages on a background queue and only hop to
  MainActor for delegate dispatch:
  ```swift
  socket?.receive { [weak self] result in
      // process on background
      self?.handleReceiveResult(result)
  }
  ```
  where `handleReceiveResult` does the JSON parse off-main and only
  `delegate?.webSocket(self, didReceiveMessage: text)` hops to main.

#### M12. `WebSocketClient.sendRaw` error handler dispatches to main but the closure already captured `self` weakly
- **File:** `Networking/WebSocketClient.swift:237-246`
- **What's wrong:**
  ```swift
  private func sendRaw(_ string: String) {
      socket?.send(.string(string)) { [weak self] error in
          if let error {
              Logger.ws.error("Send error: \(error.localizedDescription)")
              DispatchQueue.main.async {
                  self?.handleDisconnect(reason: "Send error: \(error.localizedDescription)")
              }
          }
      }
  }
  ```
  `socket?.send`'s completion runs on a URLSession background queue.
  `self?.handleDisconnect` is `@MainActor`. Wrapping in
  `DispatchQueue.main.async` is fine — but `handleDisconnect` reads
  `isManuallyDisconnected`, `isReconnecting`, etc. without actor
  isolation guarantees. The class is `@MainActor` but the compiler
  can't verify this hop.
- **Impact:** Strict concurrency may flag this; behavior is OK in
  practice but fragile.
- **Fix:**
  ```swift
  Task { @MainActor [weak self] in
      self?.handleDisconnect(reason: "Send error: \(error.localizedDescription)")
  }
  ```

#### M13. `FriendManager.init` calls `loadAll()` which can fire API requests before `authToken` is set
- **File:** `Services/FriendManager.swift:28-31`
- **What's wrong:**
  ```swift
  init() {
      Task { await loadAll() }
  }
  ```
  `loadAll` → `loadFriends` → `guard api.authToken != nil else { return }`.
  But since the FriendManager owns its own APIClient (C5), `authToken`
  is always nil. So `loadAll` is a no-op. Worse: even after fixing C5,
  if `RaveCloneApp` constructs `FriendManager` BEFORE `AuthService` has
  finished restoring the token, the `Task` may run before the token is
  available — silently returning without loading.
- **Impact:** Friends list stays empty on first launch.
- **Fix:** Trigger `loadAll` from `RaveCloneApp.checkAuth` after
  `bridgeAuthToken` completes.

#### M14. `RoomSyncManager.handleAppBackground` 30s timeout disconnects mid-room
- **File:** `Services/RoomSyncManager.swift:385-397`
- **What's wrong:** The 30s background task hard-disconnects the
  WebSocket. But iOS gives up to ~30s of background runtime for
  arbitrary tasks; if the OS kills the app before the foreground
  handler fires, `didDisconnectInBackground` stays `true` and the next
  launch starts with a stale `connectionStatus = .reconnecting`
  (impossible — the WS isn't connected).
- **Impact:** Stuck reconnecting state on cold launch.
- **Fix:** Reset `didDisconnectInBackground` in `init`:
  ```swift
  init(...) {
      ...
      didDisconnectInBackground = false
  }
  ```

#### M15. `HomeView.startCTACollapseTimer` Timer stored in `@State`
- **File:** `Views/Home/HomeView.swift:33, 469-475`
- **What's wrong:**
  ```swift
  @State private var ctaCollapseTimer: Timer?
  ...
  ctaCollapseTimer = Timer.scheduledTimer(...) { _ in
      withAnimation(...) { isCTACollapsed = true }
  }
  ```
  `Timer` is a reference type. Storing it in `@State` is allowed but
  SwiftUI may recreate the view (and reset the @State) on certain
  identity changes, leaking the prior Timer. There's no `.onDisappear`
  cleanup.
- **Impact:** Timer fires on a dismissed HomeView, possibly setting
  state on a stale view.
- **Fix:** Use a `Task` with `Task.sleep` instead, or invalidate in
  `.onDisappear`.

#### M16. `WebSocketClient` nonisolated conformance bridge uses `MainActor.assumeIsolated`
- **File:** `Networking/WebSocketClient.swift:451-455`
- **What's wrong:**
  ```swift
  nonisolated var isConnectedBridge: Bool {
      MainActor.assumeIsolated { self.isConnected }
  }
  ```
  `MainActor.assumeIsolated` crashes if called from a non-MainActor
  context. The whole point of `isConnectedBridge` is to be callable
  from anywhere — but if the caller is on a background queue, this
  traps.
- **Impact:** Crash risk if any non-MainActor code touches
  `isConnectedBridge`.
- **Fix:** Use `MainActor.assumeIsolated` only with a documented
  precondition, or provide a true async accessor.

---

### 🟢 LOW — Hygiene / Polish / Deprecations

#### L1. Hardcoded Russian strings throughout views (bypass LocalizationManager)
- **Files:** `Views/Home/HomeView.swift` (lines 175, 260, 295, 324, 518,
  575), `Views/Home/RoomCreationView.swift` (lines 69, 95, 104, 124, 142,
  147, 171, 176, 215, 224, 273, 281, 376, 418, 424, 460), `Views/Admin/AdminPanelView.swift`
  (lines 43, 60-69, 91, 163, 220, 256, 279, 285), `Views/Settings/PrivacySettingsView.swift`
- **What's wrong:** The app has a `LocalizationManager` with `L10n.Key`
  enums and three languages (ru/en/zh), but most new UI bypasses it.
- **Impact:** English and Chinese localizations are incomplete; switching
  language in settings doesn't update these screens.
- **Fix:** Add the missing keys to `L10n.Key` and use
  `loc.string(.key)`.

#### L2. `Room.mockRooms` ships with mock data (5 fake rooms with fake participants)
- **File:** `Models/Room.swift:105-143`
- **What's wrong:** Production code ships with hardcoded mock rooms
  ("Дюна 2", "Lo-Fi Chill", etc.) labeled as "fallback when server 401
  or empty". A real production app should not have fake content baked
  in.
- **Impact:** If the server returns empty/401, users see fake "active"
  rooms with fake participant counts — misleading.
- **Fix:** Remove `mockRooms` or gate behind `#if DEBUG`.

#### L3. `WSClient.connectionStats` returns untyped `[String: Any]`
- **File:** `Networking/WebSocketClient.swift:428-437`
- **What's wrong:** Returns a dictionary with mixed types (Bool, Int,
  String). Not Sendable, not type-safe.
- **Impact:** Any consumer must cast; no compile-time guarantees.
- **Fix:** Return a `struct ConnectionStats: Sendable { let connected:
  Bool; let rttMs: Int; ... }`.

#### L4. `ReactionOverlayView` is dead code
- **File:** `Views/Room/ReactionOverlayView.swift`
- **What's wrong:** The struct exists, has previews, but is never
  instantiated. `RoomView` uses `ReactionSpriteOverlay` instead.
- **Impact:** ~120 lines of dead code.
- **Fix:** Delete the file.

#### L5. `PrivacySettingsView` toggles don't persist or sync
- **File:** `Views/Settings/PrivacySettingsView.swift:8-10`
- **What's wrong:** `profileVisibility`, `onlineStatus`, `readReceipts`
  are `@State` with no `UserDefaults` persistence and no backend call.
- **Impact:** User toggles privacy → leaves screen → toggles reset.
- **Fix:** Persist to `UserDefaults` and POST to `/api/users/privacy`.

#### L6. `LoginView` Google/Apple sign-in is fake
- **File:** `Views/Auth/LoginView.swift:207-248`
- **What's wrong:** Tapping Google or Apple shows a spinner, then after
  1.5s falls back to the email form. There's no actual OAuth flow.
- **Impact:** Misleading UI. Apple Sign In is required if you offer
  third-party sign-in (Apple Guideline 4.8).
- **Fix:** Either implement real `ASAuthorizationAppleIDProvider` or
  remove Google/Apple buttons.

#### L7. `AmbilightBackground` uses `@StateObject` for a shared singleton
- **File:** `Views/Room/AmbilightBackground.swift:20`
- **What's wrong:** `@StateObject private var sampler = AmbilightSampler.shared`
  — `@StateObject` implies SwiftUI owns the lifecycle, but
  `AmbilightSampler.shared` is a singleton. Two `AmbilightBackground`
  instances would each think they own it.
- **Impact:** Conceptual misuse; works because the singleton ignores
  `@StateObject` ownership semantics.
- **Fix:** Use `@ObservedObject` for shared singletons:
  ```swift
  @ObservedObject private var sampler = AmbilightSampler.shared
  ```

#### L8. `RoomView` `shareSheetPresented` builds a wrong URL
- **File:** `Views/Room/RoomView.swift:119-123`
- **What's wrong:**
  ```swift
  .sheet(isPresented: $shareSheetPresented) {
      if let url = URL(string: "https://raveclone.com/join/\(room.code)") {
          ShareSheet(items: [url])
      }
  }
  ```
  Domain is `raveclone.com`, but `DeepLinkRouter.domain` is
  `raveclone.app`, and `ShareManager.shareBaseURL` is `raveclone.app`.
  Path is `/join/<code>`, but `DeepLinkRouter.parsePath` only
  recognizes `/r/<code>` or `/u/<userId>`. The shared URL won't
  trigger a Universal Link.
- **Impact:** Recipients of the share sheet get a URL that opens a 404
  in a browser.
- **Fix:** Use `ShareManager.shareURL(for: room.id, code: room.code)`.

#### L9. `EnergyController` observer never removed
- **File:** `Views/Room/AmbilightBackground.swift:171-181`
- **What's wrong:** `EnergyController.shared` registers a
  `NotificationCenter` observer in `init` but never removes it. Being a
  singleton, this is OK in practice — but if the class ever becomes
  non-singleton, it leaks.
- **Fix:** Add `deinit { NotificationCenter.default.removeObserver(self) }`.

#### L10. `RaveCloneApp.handleDeepLink` hardcodes "Пользователь" for friend invite
- **File:** `RaveCloneApp.swift:135`
- **What's wrong:**
  ```swift
  friendInviteAlert = FriendInviteAlert(userId: userId, username: "Пользователь")
  ```
  Username is hardcoded Russian "Пользователь" (User). The actual
  username should be fetched from the server.
- **Fix:** Fetch via `FriendManager` or a `/api/users/:id` lookup.

#### L11. `MediaService.apiBaseURL` defaults to `raveclone.app` while `APIClient.baseURL` defaults to Railway URL
- **File:** `Services/MediaService.swift:38` vs `Networking/APIClient.swift:23`
- **What's wrong:**
  - `APIClient`: `https://xpkcakpkfewp-ofewk-pkv-production.up.railway.app/api`
  - `MediaService`: `https://raveclone.app/api`
  - `YouTubeSearchService`: `https://raveclone.app/api`
  - `YandexAuthService`: `https://raveclone.app/api`
  
  Two different backend URLs. Either Railway is a staging server and
  `raveclone.app` is prod, or someone forgot to update one.
- **Impact:** Inconsistent backend. Auth/room operations go to Railway,
  media extraction goes to `raveclone.app` (which may not exist).
- **Fix:** Centralize base URL in a single `Config` struct.

#### L12. `RaveCloneApp.init` does not propagate auth token to RoomService
- **File:** `RaveCloneApp.swift:43-50`
- **What's wrong:** `RoomService(api: api)` shares the same `api` as
  `AuthService`, so once `AuthService.cacheToken` sets `api.authToken`,
  RoomService gets it for free. Good. But the same is NOT true for
  `MediaService` (line 47) — it has its own `setAuthToken` method and
  is only updated via `bridgeAuthToken()`. If `bridgeAuthToken` is
  called before `authService.currentUser` is populated (which it can
  be in `RaveCloneApp.onAppear` line 77), `getFreshToken()` returns
  the old token.
- **Fix:** Subscribe `MediaService.setAuthToken` to a token-change
  publisher in `AuthService`.

#### L13. `AuthService.deleteAccount` doesn't actually delete
- **File:** `Services/AuthService.swift:111-114`
- **What's wrong:**
  ```swift
  func deleteAccount() async throws {
      // TODO: добавить DELETE /api/auth/me на сервере
      try await signOut()
  }
  ```
  Just signs out. Account data persists on server.
- **Impact:** GDPR/CCPA right-to-delete violation.
- **Fix:** Implement `DELETE /api/auth/me` on backend and call it
  before `signOut`.

#### L14. `MarqueeMessageView.width(usingFont:)` uses `NSString.size(withAttributes:)`
- **File:** `Views/Room/MarqueeMessageView.swift:64-67`
- **What's wrong:** `NSString.size` returns an approximate size and
  doesn't account for line breaks or emoji rendering differences. Used
  to compute `scrollDistance` — if wrong, marquee either over-scrolls
  (gap visible) or under-scrolls (text cut off).
- **Impact:** Minor visual glitch on long messages with emoji.
- **Fix:** Use `Text(...).measureSize()` via `PreferenceKey` or
  `UIFont.textRect(for: range, limitedTo: width)`.

#### L15. `WebSocketClient.connectionStats` references `activeRoomID!` after nil-check
- **File:** `Networking/WebSocketClient.swift:435`
- **What's wrong:**
  ```swift
  "activeRoomID": activeRoomID ?? "none",
  ```
  This is fine — but `notifyConnectedIfNeeded` (line 421) does
  `Logger.ws.info("Restoring room session: \(activeRoomID!)")` after a
  `if activeRoomID != nil` check. Force-unwrap is safe but fragile if
  refactored.
- **Fix:** Use `if let` binding.

#### L16. `SyncEngine.deinit` touches `@MainActor` state
- **File:** `Services/SyncEngine.swift:88-92`
- **What's wrong:**
  ```swift
  deinit {
      player?.pause()
      if let observer = timeObserver { player?.removeTimeObserver(observer) }
  }
  ```
  `player` and `timeObserver` are `@MainActor`-isolated ivars of a
  `@MainActor` class. `deinit` is `nonisolated` by default in Swift 5.10+.
  Accessing these from `nonisolated deinit` is a concurrency violation.
- **Fix:** Mark `deinit nonisolated` explicitly and use
  `MainActor.assumeIsolated`, or move teardown to a `cleanup()` method
  called before release.

---

### Summary

| Severity | Count | Headline Issue |
|----------|-------|----------------|
| 🔴 Critical | 14 | WS send path never executes (C1); JWT in UserDefaults (C2); DM/Friends/Admin all use unauth clients (C4-C6); host identity hardcoded (C7); IAP bypass (C9); ads ignore premium (C10) |
| 🟠 High | 14 | Dual AVPlayer desync (H3); timer leaks in AdSessionManager/AdPlayerView (H4-H5); CVPixelBuffer use-after-free (H7); JSONEncoder race (H10); unbounded message array (H13) |
| 🟡 Medium | 16 | SyncEngine seek-vs-pulse ambiguity (M1); multi-decode routing (M3-M4); restore purchases no-op (M5); operator precedence in OrientationManager (M9) |
| 🟢 Low | 16 | Hardcoded strings (L1); mock rooms in prod (L2); dead code (L4); share URL mismatch (L8); split backend URLs (L11) |

### Top 5 fixes to ship first

1. **C1** — Fix WebSocket `isConnected` lifecycle. Without this, **nothing**
   works.
2. **C4 + C5 + C6 + AdminPanel** — Inject shared authenticated `APIClient`
   into all services. Without this, DM/Friends/Admin are 401 forever.
3. **C7 + C8** — Thread real `currentUserId` and `isPremium` from
   `AuthService.currentUser` into RoomView/RoomCreationView. Without
   this, host mode and premium ad-skipping are dead.
4. **C2 + C3 + C9** — Move JWT to Keychain, implement real token refresh,
   delete `setPremium`. Without this, the app is one jailbreak/iCloud
   backup away from full account takeover and IAP bypass.
5. **H3** — Unify on a single AVPlayer instance shared between SyncEngine
   and VideoContainerView. Without this, sync is visually broken even
   when C1 is fixed.

---

## Task ID: AUDIT-IOS-V2 — Re-Audit Delta Report (Plink iOS v2)

**Scope:** Delta audit of the renamed/refactored Plink iOS app at
`/home/z/my-project/raveclone-review-v2/Plink/`. The repo was wiped and
recreated; only the iOS Swift app remains; new "Bioluminescent Dark
Premium" design system (cyan `#2DE2E6` / teal `#0EB5C9` / emerald
`#26D9A4` on obsidian `#0A0D14`) replaces "Pure Black × Ice Glow";
`AnimatedGradientBackground.swift` reduced to a `Color.clear` placeholder;
new `BioluminescentBackground.swift` uses `Canvas` + `TimelineView(.animation)`.

**Method:** Re-read every key file from the new repo, verify each of the
original 60 bugs from `AUDIT-IOS`, and flag new regressions introduced
by the redesign. Line numbers below reference the new files.

---

### Summary table

| Severity | Original | Still present | Fixed | New |
|----------|----------|---------------|-------|-----|
| 🔴 Critical | 14       | 14            | 0     | 0   |
| 🟠 High     | 14       | 13            | 1     | 2   |
| 🟡 Medium   | 16       | 16            | 0     | 3   |
| 🟢 Low      | 16       | 16            | 0     | 2   |
| **Total**  | **60**   | **59**        | **1** | **7** |

**Headline:** Out of 60 original bugs, **only H1 was fixed**. The
redesign touched theming/backgrounds but did not address any of the
critical correctness, security, or auth-bypass issues. The new
Bioluminescent background is real and animated, but its coverage is
incomplete (20+ screens still call the now-`Color.clear`
`AnimatedGradientBackground`, so sheets/modals render on a black
backdrop), and the old palette leaks through ~30 hardcoded color
literals.

---

### Section A — Original Bugs: Status Delta

#### 🔴 Critical (C1–C14) — all still present

- **C1 — WS `isConnected` never set true** — STILL PRESENT.
  `notifyConnectedIfNeeded()` is still declared but never called:
  `WebSocketClient.swift:408 private func notifyConnectedIfNeeded()`,
  no caller anywhere in the repo (grep verified). `send(_:)` at line 221
  still short-circuits via `if isConnected { sendRaw } else { enqueue }`.
  The entire realtime send path is dead.

- **C2 — JWT in UserDefaults** — STILL PRESENT.
  `AuthService.swift:130 defaults.set(token, forKey: Keys.authToken)`.
  The `KeychainHelper` exists (`YandexAuthService.swift:238`) but is
  still only used for `yandex_jwt`, not the main `rave_auth_token`.

- **C3 — `getFreshToken()` never refreshes** — STILL PRESENT.
  `AuthService.swift:118-124`: both branches return `authToken`:
  `if authToken == nil || now >= tokenExpiry - 300 { return authToken }`
  then `return authToken`. No `/auth/refresh` call.

- **C4 — `DMChatService` owns unauth `APIClient`** — STILL PRESENT.
  `DMChatService.swift:16 private let api = APIClient()`. `api.authToken`
  is never set. `loadHistory`'s `guard api.authToken != nil else { return }`
  silently bails.

- **C5 — `FriendManager` owns unauth `APIClient`** — STILL PRESENT.
  `FriendManager.swift:26 private let api = APIClient()`. Same as C4;
  every `loadFriends`/`loadRequests`/`sendRequest`/`acceptRequest`/
  `searchUsers` will 401.

- **C6 — `AdminPanelView` owns unauth `APIClient`** — STILL PRESENT.
  `AdminPanelView.swift:8 private let api = APIClient()`. Admin panel
  cannot load or modify any data.

- **C7 — `RoomView.setupViewModel()` hardcodes `"current_user"`** — STILL PRESENT.
  `RoomView.swift:479-484`:
  ```swift
  let syncEngine = SyncEngine(wsClient: wsClient, roomID: room.id,
      userID: "current_user",
      isHost: room.hostID == "current_user")
  ```
  `viewModel = RoomViewModel(room: room, currentUserId: "current_user", …)`
  (line 488). `isHost` is `false` for every real user.

- **C8 — `RoomCreationView.createRoom()` hardcodes `hostID: "current_user"`, `hostIsPremium: false`** — STILL PRESENT.
  `RoomCreationView.swift:474 hostID: "current_user"` and
  `RoomCreationView.swift:481 hostIsPremium: false`. Also in
  `CreateRoomView.swift:328, 335`.

- **C9 — `PremiumStatusManager.setPremium(_:)` allows manual IAP bypass** — STILL PRESENT.
  `PremiumStatusManager.swift:62-72`: still callable, still writes
  `rave_user_is_premium` to `UserDefaults` (line 105). Anyone with
  filesystem access (or any caller) flips premium on.

- **C10 — `AdSessionManager.triggerAd()` skips premium check** — STILL PRESENT.
  `AdSessionManager.swift:122-136`: `triggerAd` does not call
  `shouldPlayAd(hostIsPremium:)`. The check at line 109 is still a
  standalone method no one calls. Premium hosts still get ads.

- **C11 — `DirectMessage.isOwnMessage` checks `"current_user"` sentinel** — STILL PRESENT.
  `DirectMessage.swift:19-21 var isOwnMessage: Bool { senderID == "current_user" }`.
  But `DMChatService.sendMessage` line 75 sets `senderID = me` where
  `me = currentUserId ?? "me"` (real user UUID). Own messages render
  on the wrong side.

- **C12 — Missing Info.plist privacy usage descriptions** — STILL PRESENT.
  `Info.plist` (37 lines, full file): no `NSMicrophoneUsageDescription`,
  no `NSCameraUsageDescription`, no `NSPhotoLibraryUsageDescription`,
  no `NSLocalNetworkUsageDescription`. `VoiceChatService`,
  `ScreenCaptureService`, `PlayerUIView` (displayLink + video output)
  will all crash on first invocation; App Store will auto-reject.

- **C13 — Empty entitlements file** — STILL PRESENT.
  `Plink.entitlements` (5 lines, full file): `<dict/>`. No Associated
  Domains, no IAP, no APNs. Universal Links, StoreKit 2 server-side
  verification, and push notifications all silently fail in release.

- **C14 — Yandex OAuth `clientID` is hardcoded placeholder** — STILL PRESENT.
  `YandexAuthService.swift:40 clientID: String = "yandex_client_id_placeholder"`.
  Yandex will reject with `400 invalid_client`.

#### 🟠 High (H1–H14) — 1 fixed, 13 still present

- **H1 — `scheduleReconnect` leaves `isReconnecting` stuck** — **FIXED** ✅.
  `WebSocketClient.swift:190-201` now resets the flag explicitly:
  ```swift
  func disconnect() {
      isManuallyDisconnected = true
      isReconnecting = false          // ← fix
      stopHeartbeat()
      socket?.cancel(with: .goingAway, reason: nil)
      …
  }
  ```

- **H2 — `RoomViewModel` & `RoomSyncManager` race for `wsClient.delegate`** — STILL PRESENT.
  `RoomViewModel.swift:89 wsClient.delegate = self` (in `joinRoomFlow`)
  and `RoomSyncManager.swift:101 wsClient.delegate = self` (in `connect`)
  both assign. Last assignment wins; messages arriving between the two
  assignments go to the wrong handler.

- **H3 — `VideoContainerView` creates a SECOND `AVPlayer`** — STILL PRESENT.
  `VideoContainerView.swift:135 let p = AVPlayer(playerItem: item)`.
  `SyncEngine.loadMedia` (`SyncEngine.swift:125`) also creates one.
  Two AVPlayers play the same stream independently; SyncEngine's is
  invisible, PlayerUIView's is out of sync.

- **H4 — `AdSessionManager.deinit` doesn't invalidate timers** — STILL PRESENT.
  `AdSessionManager.swift:66-68 deinit { /* Cannot touch @MainActor state */ }`.
  Comment is still wrong; `Timer.invalidate()` is safe from `nonisolated
  deinit`.

- **H5 — `AdPlayerView.startCountdown` Timer leaks on dismiss** — STILL PRESENT.
  `AdPlayerView.swift:73-88`: `Timer.scheduledTimer` invalidated only
  when `countdown <= 0`; no `.onDisappear { timer.invalidate() }`.
  Early dismiss fires `onDismiss()` ~15 more times.

- **H6 — `AudioManager.animateVolume` spawns 10 racing Tasks** — STILL PRESENT.
  `AudioManager.swift:113-121 for step in 1...steps { Task { … } }`.
  No `volumeAnimTask?.cancel()` before starting the next animation.

- **H7 — `AmbilightSampler.processFrame` CVPixelBuffer use-after-free** — STILL PRESENT.
  `AmbilightBackground.swift:79-84 Task.detached(priority: .utility) {
  [ciContext] in let extracted = await Self.extractDominantColors(from:
  pixelBuffer, context: ciContext) … }` — no `CVPixelBufferRetain`/
  `CVPixelBufferRelease`. Display-link fires at 4 Hz, throttled to 2 Hz;
  buffer can be recycled before the detached task runs.

- **H8 — `PlayerUIView` CADisplayLink leak across URL changes** — STILL PRESENT.
  `VideoContainerView.swift:114-194`: no `willMove(toSuperview:)`
  override. `deinit { displayLink?.invalidate() }` (line 191-193) is
  the only teardown; if the parent view stays alive but `mediaURL`
  changes, old display links keep firing against orphaned players.

- **H9 — `RoomView.setupViewModel` creates fresh service instances** — STILL PRESENT.
  `RoomView.swift:470-512`: `let api = APIClient()`, `let wsClient =
  WebSocketClient()`, `let roomService = RoomService(api: api)`,
  `let authService = AuthService(api: api)` — all brand-new, no auth
  token, on every appear. Nothing is injected from `PlinkApp`.

- **H10 — `APIClient.encoder/decoder` shared mutable state on `Sendable`** — STILL PRESENT.
  `APIClient.swift:7-18`: `private let encoder: JSONEncoder` and
  `private let decoder: JSONDecoder` on a `final class APIClient: Sendable`.
  Both coders are not thread-safe; concurrent `request<T>` calls share
  them.

- **H11 — `APIClient.request<T>` cannot handle 204 No Content** — STILL PRESENT.
  `APIClient.swift:62-64 case 200..<300: return try decoder.decode(T.self,
  from: data)`. Empty body still throws a decoding error.

- **H12 — `WebSocketClient nonisolated(unsafe) var socket`** — STILL PRESENT.
  `WebSocketClient.swift:53 private nonisolated(unsafe) var socket:
  URLSessionWebSocketTask?`. Touched from `connectInternal`, `disconnect`,
  `cancelSocketForDeinit`, and `sendRaw`'s closure on a background
  queue. No actual synchronization.

- **H13 — `RoomViewModel.messages` unbounded** — STILL PRESENT.
  `RoomViewModel.swift:13 var messages: [ChatMessage] = []` with no cap.
  `routeInbound` line 234 `messages.append(chatMsg)` — never trims.

- **H14 — `AuthService.init` mutates `currentUser` from detached Task** — STILL PRESENT.
  `AuthService.swift:32-35 Task { @MainActor in self.currentUser = user }`
  spawned from non-isolated `init`. `PlinkApp.checkAuth` calls
  `authService.currentUser()` immediately after init — race on cold
  launch flashes LoginView.

#### 🟡 Medium (M1–M16) — all still present

- **M1 — `SyncEngine.handleSeek` extrapolation heuristic** — STILL PRESENT.
  `SyncEngine.swift:398 let isStatePulse = elapsedSinceEvent <
  Constants.stateBroadcastInterval + 1`. Real seeks within 3s of a
  broadcast are silently reverted to the broadcast position.

- **M2 — `SignalingMessage.decode` string-substring detection** — STILL PRESENT.
  `SignalingMessage.swift:43-44 guard raw.contains("\"kind\"") else {
  return nil }`. Chat text containing the literal `"kind"` is attempted
  as signaling.

- **M3 — `RoomViewModel.routeInbound` decodes every msg up to 4×** — STILL PRESENT.
  `RoomViewModel.swift:221, 228, 233, 239` — `SyncMessage`, then
  `voiceChat.ingest`, then `ChatMessage`, then `ParticipantUpdate`,
  then `RoomClosedPayload`. Up to 5 decode attempts per inbound frame.

- **M4 — `RoomSyncManager.handleRawMessage` decodes every msg up to 4×** — STILL PRESENT.
  `RoomSyncManager.swift:199-218`: `WSPingPong`, `AdCommandPayload`,
  `SyncMessage`, `RoomEventEnvelope` all attempted in sequence.

- **M5 — `StoreManager.restorePurchases` doesn't actually restore** — STILL PRESENT.
  `StoreManager.swift:115-126`: only calls `AppStore.sync()`. Does not
  iterate `Transaction.currentEntitlements` or call
  `handleSuccessfulPurchase`. Restore button is a no-op for finished
  transactions.

- **M6 — `PremiumStatusManager.isPremium` loaded from `UserDefaults`** — STILL PRESENT.
  `PremiumStatusManager.swift:112-133 loadPersistedState()` reads
  `rave_user_is_premium` and trusts it. Combined with C9, the local
  premium state is fully attacker-controlled.

- **M7 — `APIClient.requestNoBody` missing 404 handling** — STILL PRESENT.
  `APIClient.swift:124-131`: switch handles `401` and `default`; no
  `case 404: throw .notFound`. Callers of `leaveRoom`/`deleteRoom`/
  `removeFriend` cannot distinguish "not found" from generic server
  error.

- **M8 — `Room.isHost` always returns `false`** — STILL PRESENT.
  `Room.swift:25-28 var isHost: Bool { false }`. Dead computed
  property; comment lies.

- **M9 — `OrientationManager.isPortrait` operator-precedence bug** — STILL PRESENT.
  `OrientationManager.swift:38-48`: still has
  `.interfaceOrientation.isPortrait ?? true && (UIDevice.current.orientation
  == .unknown …)`. `??` binds looser than `&&`, so the right operand
  parses as `?? (true && (...))`. Returns `true` for landscape when
  device is flat.

- **M10 — `RoomView` calls `voiceChat.startCall` twice** — STILL PRESENT.
  `RoomView.swift:82-84`:
  ```swift
  await viewModel.joinRoomFlow()        // calls startCall at line 97
  try? await voiceChat?.startCall(roomId: room.id)  // calls it AGAIN
  ```
  `joinRoomFlow` (line 97) already calls `try await voiceChat.startCall(roomId: room.id)`.

- **M11 — `handleReceiveResult` recursively re-arms receive on MainActor** — STILL PRESENT.
  `WebSocketClient.swift:260-293`: each receive hop is one full
  MainActor cycle (`Task { @MainActor in handleReceiveResult }`).
  A 100-message burst serializes through 100 main-actor hops.

- **M12 — `sendRaw` error handler dispatches to main but uses `DispatchQueue.main.async`** — STILL PRESENT.
  `WebSocketClient.swift:237-246`: closure on URLSession background
  queue wraps `self?.handleDisconnect(…)` in
  `DispatchQueue.main.async { … }` instead of `Task { @MainActor in … }`.
  Compiler can't verify isolation; strict concurrency flag.

- **M13 — `FriendManager.init` calls `loadAll()` before `authToken` set** — STILL PRESENT.
  `FriendManager.swift:28-31 init() { Task { await loadAll() } }`.
  Even if C5 were fixed, `RaveCloneApp` constructs `FriendManager`
  (line 19) before `AuthService` has propagated the token. `loadAll`
  no-ops.

- **M14 — `RoomSyncManager.handleAppBackground` stale `didDisconnectInBackground`** — STILL PRESENT.
  `RoomSyncManager.swift:81 didDisconnectInBackground = false` (init
  default), but `handleAppBackground` (line 394) sets it to `true` and
  only `handleAppForeground` (line 404) resets it. If the OS kills the
  app mid-background, the next cold launch starts with stale
  `.reconnecting` state — but actually `init` defaults it to `false`,
  so the original "stuck on cold launch" concern is mitigated. Still
  PARTIAL: `connectionStatus = .reconnecting` (line 405) is set before
  `connect()` returns; if `connect()` fails synchronously the user
  sees `.reconnecting` for a non-existent connection. Verified still
  present.

- **M15 — `HomeView.startCTACollapseTimer` Timer in `@State`** — STILL PRESENT.
  `HomeView.swift:33 @State private var ctaCollapseTimer: Timer?`,
  lines 483-500 schedule a `Timer.scheduledTimer`. No `.onDisappear`
  cleanup; SwiftUI identity change can leak the prior timer.

- **M16 — `WebSocketClient.isConnectedBridge` uses `MainActor.assumeIsolated`** — STILL PRESENT.
  `WebSocketClient.swift:451-455`:
  ```swift
  nonisolated var isConnectedBridge: Bool {
      MainActor.assumeIsolated { self.isConnected }
  }
  ```
  Crashes if called from a non-MainActor context.

#### 🟢 Low (L1–L16) — all still present

- **L1 — Hardcoded Russian strings** — STILL PRESENT. Verified in
  `RoomCreationView.swift:255 "Назад"`, `:376 "Запустить комнату"`,
  `:352 "В сети"/"Не в сети"`, `ProfileView.swift:545 "Сохранить"`,
  `:560 "Отмена"`, `MainTabView.swift:401 "Отмена"`, `PaywallView.swift:281
  "Отмена в любой момент…"`, `DMChatView.swift:26 "Сегодня"`, etc.

- **L2 — `Room.mockRooms` ships in prod** — STILL PRESENT.
  `Room.swift:105-143 static var mockRooms: [Room]` — six fake rooms
  ("Дюна 2", "Lo-Fi Chill", …) used as fallback. No `#if DEBUG` gate.

- **L3 — `connectionStats` returns untyped `[String: Any]`** — STILL PRESENT.
  `WebSocketClient.swift:428-437` returns mixed Bool/Int/String dict;
  not Sendable.

- **L4 — `ReactionOverlayView.swift` dead code** — STILL PRESENT.
  File still exists, never instantiated (grep returns only the file
  itself).

- **L5 — `PrivacySettingsView` toggles don't persist** — STILL PRESENT.
  `PrivacySettingsView.swift:8-10 @State private var profileVisibility =
  true` etc. — no `UserDefaults`, no backend call.

- **L6 — `LoginView` Google/Apple is fake** — STILL PRESENT.
  `LoginView.swift:235-243 DispatchQueue.main.asyncAfter(deadline:
  .now() + 1.5) { selectedAuthMethod = .email }` — 1.5s spinner then
  fallback to email form. No `ASAuthorizationAppleIDProvider`.

- **L7 — `AmbilightBackground` uses `@StateObject` for singleton** — STILL PRESENT.
  `AmbilightBackground.swift:20 @StateObject private var sampler =
  AmbilightSampler.shared`.

- **L8 — `RoomView` share sheet URL still wrong** — STILL PRESENT.
  `RoomView.swift:121 URL(string: "https://raveclone.com/join/\(room.code)")`.
  Domain `raveclone.com` ≠ `DeepLinkRouter.domain` ("raveclone.app")
  ≠ `ShareManager.shareBaseURL` ("https://raveclone.app"). Path
  `/join/<code>` ≠ `DeepLinkRouter.parsePath`'s recognized `/r/<code>`
  or `/u/<userId>`. Shared URLs return 404.

- **L9 — `EnergyController` observer never removed** — STILL PRESENT.
  `AmbilightBackground.swift:171-181 init` registers
  `NSProcessInfoPowerStateDidChange` observer; singleton, no `deinit`.

- **L10 — `handleDeepLink` hardcodes "Пользователь"** — STILL PRESENT.
  `RaveCloneApp.swift:139 friendInviteAlert = FriendInviteAlert(userId:
  userId, username: "Пользователь")`.

- **L11 — Split backend URLs** — STILL PRESENT.
  `APIClient.swift:23 baseURL: "https://xpkcakpkfewp-ofewk-pkv-production.up.railway.app/api"`
  vs `MediaService.swift:38 apiBaseURL: "https://raveclone.app/api"`,
  `YandexAuthService.swift:42 backendURL: URL(string:
  "https://raveclone.app/api")`. Three different backend URLs.

- **L12 — `PlinkApp.init` doesn't propagate token to `MediaService`** — STILL PRESENT.
  `RaveCloneApp.swift:47 mediaService = MediaService()` — `MediaService`
  has its own `authToken` and is updated only via `bridgeAuthToken()`
  (line 158 `mediaService.setAuthToken(token)`). If `bridgeAuthToken`
  runs before `AuthService` populates `authToken`, `MediaService`
  keeps the stale token. Same architecture as before.

- **L13 — `AuthService.deleteAccount` doesn't delete** — STILL PRESENT.
  `AuthService.swift:111-114 func deleteAccount() async throws {
  // TODO: добавить DELETE /api/auth/me на сервере
  try await signOut() }`.

- **L14 — `MarqueeMessageView.width(usingFont:)` uses `NSString.size`** — STILL PRESENT.
  `MarqueeMessageView.swift:64-67 return (self as
  NSString).size(withAttributes: attributes).width`.

- **L15 — `notifyConnectedIfNeeded` force-unwraps `activeRoomID!`** — STILL PRESENT.
  `WebSocketClient.swift:421 Logger.ws.info("Restoring room session:
  \(activeRoomID!)")` after `if activeRoomID != nil` (line 420). Safe
  today; fragile under refactor.

- **L16 — `SyncEngine.deinit` touches `@MainActor` state** — STILL PRESENT.
  `SyncEngine.swift:88-92 deinit { player?.pause(); if let observer =
  timeObserver { player?.removeTimeObserver(observer) } }` — `player`
  and `timeObserver` are `@MainActor`-isolated ivars; default
  `nonisolated deinit` violates concurrency.

---

### Section B — New Bugs Introduced by the Redesign

#### 🟠 N1 — Bioluminescent background has incomplete coverage
- **Files:** 20 screens still call `AnimatedGradientBackground()`:
  `Views/Chat/ChatView.swift:26`, `Views/Chat/DMChatView.swift:18`,
  `Views/Premium/PaywallView.swift:25`, `Views/Admin/AdminPanelView.swift:38`,
  `Views/Settings/PrivacySettingsView.swift:15`,
  `Views/Settings/SettingsSlidePanel.swift:335`,
  `Views/Settings/NotificationsView.swift`,
  `Views/Settings/LanguagePickerView.swift`,
  `Views/Home/HomeView.swift:55`, `Views/Home/RoomCreationView.swift:37`,
  `Views/Home/CreateRoomView.swift:35`, `Views/Home/ServiceSelectionView.swift:253`,
  `Views/Home/YouTubeSearchView.swift`, `Views/Room/ParticipantListView.swift:10`,
  `Views/Friends/FriendsView.swift`, `Views/Friends/FriendProfileView.swift`,
  `Views/AI/AIAssistantView.swift:18`, `Views/Components/MainTabView.swift:88`,
  `Views/Profile/ProfileView.swift`, plus the deprecated
  `Views/Components/AnimatedGradientBackground.swift:11` itself.
- **What's wrong:** `AnimatedGradientBackground` is now `Color.clear.ignoresSafeArea()`
  (file line 17). `Color.clear` is transparent — fine for tab content
  where the root `BioluminescentBackground` shows through, but every
  screen presented as a `.sheet` / `.fullScreenCover` / modal
  `NavigationStack` (PaywallView, AdminPanelView, PrivacySettingsView,
  ParticipantListView, ChatView, DMChatView, CreateRoomView,
  RoomCreationView, etc.) renders against the sheet's own dimmed/black
  backdrop with no bioluminescent theme. The "Bioluminescent Dark
  Premium" look is broken on every modal.
- **Impact:** Major visual regression. Every modal sheet appears
  dark/black instead of glowing cyan/teal/emerald. The redesign
  promise is unfulfilled on the screens where it matters most (paywall,
  create-room flow).
- **Fix:** Replace `AnimatedGradientBackground()` calls in sheets with
  `BioluminescentBackground()` directly. Delete the `AnimatedGradientBackground`
  struct entirely or make it `@available(*, deprecated, message: "Use
  BioluminescentBackground")` returning `BioluminescentBackground()`.

#### 🟠 N2 — `AnimatedGradientBackground` silently drops parameters
- **File:** `Views/Components/AnimatedGradientBackground.swift:11-19`
- **What's wrong:**
  ```swift
  struct AnimatedGradientBackground: View {
      var orbColors: [Color] = []
      var hasActiveRooms: Bool = true
      var body: some View { Color.clear.ignoresSafeArea() }
  }
  ```
  Callers still pass `orbColors: [Color(hex: 0x3D8DE0), …]`
  (`PaywallView.swift:26`), `orbColors: [Color(hex: 0xFF3D8B), …]`
  (`AdminPanelView.swift:38`), `orbColors: [Color(hex: 0x9B59B6), …]`
  (`SettingsSlidePanel.swift:335`), `orbColors: [Color(hex: 0x7B2CBF),
  …]` (`AIAssistantView.swift:18`), `hasActiveRooms: true/false`
  (HomeView). All silently ignored. No compiler warning. Authors think
  their custom per-screen palettes are still rendered.
- **Impact:** Deceptive API. Future maintainers will "tune" the colors
  and see no effect. Combined with N1, the screens render with no
  background at all.
- **Fix:** Either delete the parameters and remove from call sites, or
  forward them to `BioluminescentBackground(palette:)`. Cleanest: delete
  the wrapper and migrate call sites.

#### 🟡 N3 — `DirectMessage.isOwnPremium` uses `MainActor.assumeIsolated` from a non-isolated computed property
- **File:** `Models/DirectMessage.swift:25-28`
- **What's wrong:**
  ```swift
  var isOwnPremium: Bool {
      guard isOwnMessage else { return false }
      return MainActor.assumeIsolated { PremiumStatusManager.shared.isPremium }
  }
  ```
  `DirectMessage` is a plain `Codable` struct with no actor isolation.
  `MainActor.assumeIsolated` traps if called from a non-MainActor
  context. Today the only call sites are in `DMChatView` `@ViewBuilder`
  bodies (`DMChatView.swift:200, 219`), so it happens to work — but the
  struct has no compile-time protection. Any future caller decoding a
  DM off-main and reading `isOwnPremium` will crash.
- **Impact:** Latent crash. Mirrors M16's pattern but on a model type.
- **Fix:** Pass `isOwnPremium: Bool` in from the view layer at
  construction time, or make this a method `isOwnPremium(on mainActor:)`
  that requires `@MainActor` caller.

#### 🟡 N4 — Old color palette leaks through ~30 hardcoded literals
- **Files:** `Views/Chat/DMChatView.swift:223-225` (`0x6EC1E4`, `0x9B59B6`,
  `0x6EC1E4` — purple shimmer for premium DMs), `Views/Profile/ProfileView.swift:413-417,
  436-437, 472, 479` (`0x6EC1E4`, `0xFF3D8B`), `Views/Home/HomeView.swift:625-626,
  772-775` (`0xFF3D8B`, `0xE8B339`, `0xFF6B35`, `0x22D3EE`), `Views/Premium/PaywallView.swift:26,
  80, 83` (`0x3D8DE0`, `0x6EC1E4`, `0x113CCF`), `Views/Admin/AdminPanelView.swift:38`
  (`0xFF3D8B`, `0x6EC1E4`, `0xE8B339`), `Views/AI/AIAssistantView.swift:18, 83`
  (`0x7B2CBF`, `0xFF3D8B`), `Views/Settings/SettingsSlidePanel.swift:335, 344`
  (`0x9B59B6`, `0xF1C40F`, `0x6EC1E4`), `Views/Home/ServiceSelectionView.swift:253`
  (`0x22D3EE`, `0x6EC1E4`, `0x1A2A6C`).
- **What's wrong:** The new design system is strict cyan/teal/emerald
  (`Color+Theme.swift:28-32`). These literals are old palette: pink
  (`0xFF3D8B`), gold (`0xE8B339`, `0xF1C40F`), orange (`0xFF6B35`),
  purple (`0x9B59B6`, `0x7B2CBF`), light-blue (`0x6EC1E4`), navy
  (`0x113CCF`, `0x1A2A6C`). Some are passed to the now-ignored
  `AnimatedGradientBackground(orbColors:)` (silently dropped), but
  others are used in actual `LinearGradient`/`RadialGradient`/`.shadow`
  calls (e.g. DMChatView premium shimmer line 221-229, ProfileView line
  472, HomeView line 625) — those DO render and break the visual
  contract.
- **Impact:** Visual inconsistency. Premium DM bubbles shimmer in
  pink-purple instead of cyan-emerald. Profile header glows pink.
  Discovery cards have orange/pink hover gradients.
- **Fix:** Replace every hardcoded literal with `Color.bioCyan` /
  `.bioTeal` / `.bioEmerald` (or the existing semantic aliases). Or —
  for non-themed accents — define them as new tokens in `Color+Theme`
  with intentional justification. Add a linter to ban `Color(hex: 0x…)`
  outside `Color+Theme.swift`.

#### 🟡 N5 — `NickStyle` enum still uses legacy colors that contradict the new palette
- **File:** `Services/PremiumStatusManager.swift:138-198`
- **What's wrong:** `NickStyle.neonPurple = .purple/.blue`,
  `.neonPink = .pink/0xFF3D8B`, `.gold = .orange/.yellow`,
  `.fire = .red/.orange/.yellow`, `.ice = .blue/.cyan/.white`,
  `.neonGreen = .green/.mint`. None of these match the strict
  cyan/teal/emerald spectrum mandated by the redesign.
  `Color+Theme.swift:43-48` explicitly remaps `ravePurple → bioTeal`
  and `raveWarning → bioEmerald` precisely to kill these old colors —
  but `NickStyle` bypasses the semantic tokens and uses `Color.purple`,
  `.pink`, `.orange`, etc. directly.
- **Impact:** Premium users who pick "Gold" or "Fire" nick style get
  orange/yellow text — breaking the bioluminescent aesthetic the user
  paid for. Inconsistent with `raveGradient` (cyan→teal) and
  `bioNeonRing` (cyan→emerald) used everywhere else.
- **Fix:** Either redesign each `NickStyle` variant as a
  cyan/teal/emerald derivative (e.g. gold → emerald + warm-shifted),
  or document that nick styles are an intentional exception and
  gate them behind `PremiumStatusManager.canCustomizeNick`.

#### 🟢 N6 — `BioEnergy` class is dead code
- **File:** `Views/Components/BioluminescentBackground.swift:143-167`
- **What's wrong:** `final class BioEnergy: ObservableObject` is
  declared with `pulse(_:)`, `setVoiceLevel(_:)`, `@Published var
  energy`/`voicePulse` — but no view in the codebase instantiates it
  (grep returns only the declaration). Furthermore, it's a non-
  `@MainActor` `ObservableObject` whose `pulse()` spawns a
  `Task { … await MainActor.run { self.energy = … } }` — the
  mutation happens on MainActor (correct), but the class is
  non-isolated and could be constructed from anywhere.
- **Impact:** ~25 lines of dead code + a concurrency smell.
- **Fix:** Delete the class, or wire it into `BioluminescentBackground`
  via `@StateObject` to actually drive the `energy` parameter.

#### 🟢 N7 — `LoginView` bypasses Bioluminescent theme, uses its own static orb layout
- **File:** `Views/Auth/LoginView.swift:43-61`
- **What's wrong:**
  ```swift
  ZStack {
      Color.raveBackground.ignoresSafeArea()
      VStack {
          Spacer()
          Circle().fill(Color.ravePrimary.opacity(0.06)).frame(width: 300, height: 300).blur(radius: 80)
          Circle().fill(Color.raveAccent.opacity(0.04)).frame(width: 250, height: 250).blur(radius: 60)
          Spacer()
      }
  }
  ```
  `Color.raveBackground` (= `0x0A0D14`) is opaque, so it covers the
  root `BioluminescentBackground` from `PlinkApp.body`. The login
  screen renders a static obsidian with two blurred circles — no
  animated drifting clouds, no noise texture. Inconsistent with the
  app's "Premium" first impression.
- **Impact:** Login flow visually flat compared to the rest of the app.
- **Fix:** Replace the `Color.raveBackground + VStack { Circle… }`
  block with a plain `BioluminescentBackground()` (and let the root
  one show through).

---

### Section C — Original Background Bug

**Original AUDIT-IOS did NOT explicitly enumerate an "AnimatedGradientBackground
didn't animate" bug** among C1–L16. However, the redesign brief asserts
that the old `AnimatedGradientBackground` was static and that the new
`BioluminescentBackground` fixes animation.

**Verification of `BioluminescentBackground` (`Views/Components/BioluminescentBackground.swift:12-120`):**
- ✅ Animates: `TimelineView(.animation) { timeline in Canvas { context,
  size in let t = timeline.date.timeIntervalSinceReferenceDate;
  drawClouds(context: context, size: size, time: t) } }` (lines 18-24).
  Four clouds drift via Lissajous-like trajectories (`sin(time * speed
  + phase)` at line 67), with pulsating radius and brightness. ~60-120
  FPS via GPU-accelerated Canvas.
- ✅ Renders depth: `drawDepth` fills obsidian `#0A0D14` (line 51).
- ✅ Renders noise overlay (line 36-41) for premium grain texture.
- ⚠️  Caveat (per N1 above): only renders when actually placed in the
  view tree. The root `PlinkApp.body` places it (line 58), so tab
  content sees it through transparent overlays. But sheets/modals
  that use the now-`Color.clear` `AnimatedGradientBackground` see
  nothing bioluminescent.

**Verification of the `AnimatedGradientBackground` placeholder (`Views/Components/AnimatedGradientBackground.swift:11-20`):**
- ✅ Reduced to `Color.clear.ignoresSafeArea()` as the brief states.
- ⚠️  But the `orbColors` and `hasActiveRooms` parameters are silently
  ignored (N2), and 20 call sites still pass them expecting the old
  behavior.

**Verdict:** Background animation IS implemented and works where
applied. Coverage is incomplete (N1); parameters are silently dropped
(N2); login screen bypasses it (N7).

---

### Section D — Top 5 New Priorities

Re-ranked across **original + new** bugs, in order of fix ROI for the
v2 redesign:

1. **C1 — Wire up `notifyConnectedIfNeeded()` (or replace with an
   explicit open-probe).** Without this, no realtime path works:
   chat, reactions, play/pause/seek, signaling all silently drop.
   One-line fix in `connectInternal()`:
   ```swift
   task.resume(); socket = task; receiveMessage()
   Task { @MainActor [weak self] in
       try? await Task.sleep(nanoseconds: 250_000_000)
       self?.notifyConnectedIfNeeded()
   }
   ```

2. **C4 + C5 + C6 + H9 — Inject the shared authenticated `APIClient`
   (and `WebSocketClient`, `AuthService`, `RoomService`) from `PlinkApp`
   into `DMChatService`, `FriendManager`, `AdminPanelView`, and
   `RoomView.setupViewModel`.** One architectural change unlocks DMs,
   friends, admin, and the entire room session. Right now every one of
   those services constructs `APIClient()` with `authToken == nil` and
   every REST call 401s.

3. **C7 + C8 + C10 + C11 — Thread real user identity through the room
   layer.** Replace `"current_user"` everywhere with
   `authService.currentUser?.id` (C7), resolve real `hostID` and
   `hostIsPremium` from `PremiumStatusManager.shared.isPremium` in
   `RoomCreationView.createRoom` (C8), call
   `shouldPlayAd(hostIsPremium:)` at the top of
   `AdSessionManager.triggerAd` (C10), and pass real user id into
   `DirectMessage.isOwnMessage` comparison (C11). Without these, host
   mode is dead, premium ad-skip is dead, and your own DMs render on
   the wrong side.

4. **N1 + N2 + N7 — Finish the Bioluminescent redesign coverage.**
   Replace the 20 `AnimatedGradientBackground()` calls in
   sheets/modals with `BioluminescentBackground()`, delete the
   deprecated wrapper (or forward its parameters), and switch
   `LoginView` to use the real background. Otherwise the redesign's
   "Premium" promise is broken on the screens where it matters most
   (paywall, create-room, login).

5. **C2 + C3 + C9 + M5 + M6 — Close the auth/IAP hole.** Move JWT to
   `KeychainHelper` (C2), implement real `/auth/refresh` (C3), delete
   `PremiumStatusManager.setPremium` and source `isPremium` from
   server `User.isPremium` (C9, M6), and make
   `StoreManager.restorePurchases` actually iterate
   `Transaction.currentEntitlements` (M5). Without this, the app is
   one jailbreak/iCloud backup away from full account takeover and
   IAP bypass — guaranteed App Review rejection.

**Bonus quick wins** (low effort, high cleanup value):
- **H4 + H5 + H6 + H8** — add `nonisolated deinit { timer?.invalidate()
  }` / `displayLink?.invalidate()` to the timer-owning services; cancel
  prior `volumeAnimTask` before starting a new one.
- **C12 + C13 + C14** — paste the four missing Info.plist privacy
  strings, add the three entitlements keys, move the Yandex `clientID`
  into an xcconfig. Three config edits unlock voice chat, screen
  capture, IAP, Universal Links, push, and Yandex OAuth in one sitting.
- **L4** — delete `ReactionOverlayView.swift`.
- **L8** — swap `URL(string: "https://raveclone.com/join/\(room.code)")`
  for `ShareManager.shareURL(for: room.id, code: room.code)`.

---

**Conclusion:** The v2 refactor modernized the visual identity but
left every functional bug from v1 in place. Net delta: 1 fixed (H1),
7 new (N1–N7). The app is still non-functional for DMs, friends,
admin, room hosting, IAP, ads, push, deep links, voice, and screen
capture — and now also ships a redesign that doesn't apply to most
modal screens. Recommend treating the v2 redesign as a visual-only
pass and scheduling a v3 focused purely on the 14 critical bugs.


---

## Task ID: FULL-AUDIT-FINAL — Final Comprehensive Audit of Plink iOS App

**Scope:** Final full-project audit of `/home/z/my-project/raveclone-review-v2/Plink/`
covering 50+ Swift files across Views, Services, Networking, ViewModels, Models,
Extensions, Resources, project.yml, Info.plist, entitlements, and assets.

**Method:** Line-by-line read of every file in the audit checklist. No code was
modified — analysis only. Findings are categorized by severity with file:line
references and concrete impact assessments.

---

### 1. COMPILATION CHECK — ❌ WILL NOT COMPILE

The project has **two hard compile errors** that block any successful Xcode build.
Both are obvious from a 5-second read of the offending files, but neither was
caught by previous audits.

#### 🛑 COMPILE ERROR #1: `FriendManager()` called with no args (4 sites)

**`Plink/Services/FriendManager.swift:34`** declares:
```swift
init(api: APIClient) {
    self.api = api
}
```
This is the ONLY initializer on the class — no `convenience init()`, no default
parameter (`api: APIClient = ...`). Swift does NOT generate a memberwise init
for classes that declare their own init.

But the following four call sites pass **no arguments**:

| File | Line | Code |
|------|------|------|
| `Plink/Views/Friends/FriendsView.swift` | 8 | `@State private var friendManager = FriendManager()` |
| `Plink/Views/Components/MainTabView.swift` | 345 | `@State private var friendManager = FriendManager()` (in `FriendsTabContent`) |
| `Plink/Views/Home/RoomCreationView.swift` | 10 | `var friendManager: FriendManager = FriendManager()` |
| `Plink/Views/Profile/ProfileView.swift` | 18 | `@State private var friendManager = FriendManager()` |

**Impact:** Project will not compile. Even if the property is never read, Swift
must type-check the initializer call.

**Fix:** Either inject the shared `FriendManager` via `@EnvironmentObject`
(consistent with `RaveCloneApp.swift:55` and `:105` which already creates and
injects one), OR add `convenience init() { self.init(api: APIClient()) }` to
`FriendManager`. The first option is correct architecturally; the second is a
minimal patch.

#### 🛑 COMPILE ERROR #2: `self.errorMessage` on `AIAssistantView` (undeclared)

**`Plink/Views/AI/AIAssistantView.swift:283`** inside the streaming error
handler:
```swift
self.errorMessage = error.localizedDescription
```
But `AIAssistantView` (struct, lines 6-17) declares only: `messages`, `inputText`,
`isLoading`, `isInputFocused`, `charLimit`, `lastSendTime`, `storageKey`. There
is **no `errorMessage` property** on the view struct. (`AIService.shared.errorMessage`
exists, but `self` here is the view, not the service.)

**Impact:** Project will not compile.

**Fix:** Add `@State private var errorMessage: String?` to `AIAssistantView`,
or remove the assignment (it's never read elsewhere in the view).

---

### 2. FUNCTIONAL CHECK — Feature Path Analysis

| Feature | Status | Notes |
|---------|--------|-------|
| **Auth (signin → token stored → token used)** | ⚠️ Partial | `AuthService` stores JWT in Keychain (C2 fixed). But `MainTabView.HomeTabContent` (line 332) and `HomeView` profile sheet (line 110) create **fresh unauthenticated `APIClient()` instances** instead of using the shared injected one. Home tab API calls will 401. |
| **Room creation (ServiceSel → Browser → Setup → appears in "Мои комнаты")** | ⚠️ Partial | `RoomSetupView.createRoom()` (line 287) builds a local `Room` and calls `onRoomCreated(room)` — but **never calls `RoomService.createRoom()` REST endpoint**. The room is local-only until something else persists it. `myRooms` will not refresh from server. |
| **Room join (code entry → join → enter room)** | ✅ OK | `HomeViewModel.joinRoom(code:)` → `RoomService.joinRoom(code:)` → POST /rooms/join → returns Room → navigation push to RoomView. |
| **Sync (host play/pause/seek → WS → guests → SyncEngine)** | ⚠️ Works but with arch issues | SyncEngine handles host commands correctly with latency compensation. BUT see issue #3 below — `RoomSyncManager` is dead code due to delegate overwrite. |
| **Chat (room chat → WS send → server broadcast → receive → display)** | ✅ OK | `RoomViewModel.routeInbound` (line 225) routes chat via `senderID` discriminator → appends to `messages`. Display via `RoomChatView`. |
| **DM (send → API POST → history load)** | ✅ OK | `DMChatService` (injected from app) → `sendMessage()` does optimistic UI + POST /messages/dm. `loadHistory(friendId:)` GET /messages/dm/:friendId. |
| **Friends (search → send → accept → list)** | ⚠️ Partial | `FriendManager` itself is correct, but `FriendsView` (line 8) creates its own local `FriendManager()` (compile error, see #1) instead of using the shared `@EnvironmentObject`. If patched with convenience init, the local instance won't share state with the app-level one. |
| **AI (tab → send → OpenRouter streaming → display)** | ✅ OK | `AIService.chatStream()` AsyncThrowingStream → tokens appended to `messages[last].text` live. Pulsing cursor. (Compile error #2 breaks the error path.) |
| **Settings (full-screen → NavigationLink push)** | ✅ OK | `SettingsView` uses `NavigationStack(path:)` + `navigationDestination(for: SettingsDestination.self)` for privacy/notifications/language push. Apple ID-style card layout. |
| **Premium (IAP → StoreManager → activatePremium)** | ✅ OK | `StoreManager.purchase()` → StoreKit 2 verification → `PremiumStatusManager.activatePremium(expiryDate:)`. `restorePurchases()` walks `Transaction.currentEntitlements`. Product IDs `com.syncwatch.raveclone.premium.*` (inconsistent with bundle ID `com.syncwatch.plink` but functional). |

---

### 3. SYNC VERIFICATION — Detailed Path Analysis

#### Outbound (host → server → guests):

1. **`SyncEngine.play()` (line 154)**: guards `isHost`, calls `player?.play()`, builds `SyncMessage(command: .play, mediaTime: currentTime, timestamp: currentServerTime)`, calls `broadcast(msg)`.
2. **`SyncEngine.broadcast(_:)` (line 551)**: encodes to JSON, calls `wsClient.send(string)`.
3. **`WebSocketClient.send(_ string:)` (line 248)**: if `isConnected` → `sendRaw(string)`; else enqueue. ✓ (C1 fix verified — `notifyConnectedIfNeeded` is now called from `handleReceiveResult` line 308 and the proactive 250ms probe at line 206-215.)
4. Server receives, broadcasts to all room participants including sender.

#### Inbound (guests receive):

5. **`WebSocketClient.handleReceiveResult` (line 302)**: calls `notifyConnectedIfNeeded()` then `handleMessage(text)` → `delegate?.webSocket(self, didReceiveMessage: text)`.
6. **Delegate routing**: HERE'S THE ARCHITECTURAL BUG — see "Sync Issue" below.

#### Sync Engine handlers:

7. **`SyncEngine.handleSyncMessage(_:)` (line 210)**: ignores echoes (`guard message.senderID != userID`), then dispatches:
   - `handlePlay` (line 341): latency compensation with `currentServerTime - eventServerTime`, caps predictive jump at 5s, fast path if drift < 2s.
   - `handlePause` (line 385): immediate pause + async seek to exact frame.
   - `handleSeek` (line 415): FIX M1 — distinguishes state pulse vs real seek via `mediaTimeDelta` (not `elapsedSinceEvent`).
   - `handleStateResponse`, `handleForcedCorrection`: drift recovery paths.

These handlers look correct and well-instrumented.

#### ⚠️ Sync Issue: `RoomSyncManager` is dead code

In **`RoomView.setupViewModel()` (lines 509-570)**:

```swift
let wsClient = WebSocketClient()                    // line 513
// ... 
let vm = RoomViewModel(...)                          // line 542 (wsClient injected)
let manager = RoomSyncManager(wsClient: wsClient, roomID: room.id)  // line 554
manager.onPlayCommand  = { pos in vm.syncEngine.seek(to: pos); ... }  // line 555
manager.onPauseCommand = { pos in vm.syncEngine.seek(to: pos); ... }  // line 559
manager.onSeekCommand  = { pos in vm.syncEngine.seek(to: pos) }       // line 563
manager.connect()                                    // line 565 — sets wsClient.delegate = self (RoomSyncManager)
viewModel = vm
syncManager = manager
```

Then **`.task { await viewModel.joinRoomFlow() }` (line 84-97)** runs after, which
on line 94 calls `wsClient.delegate = self` (RoomViewModel) — **OVERWRITING**
the RoomSyncManager delegate.

After this sequence:
- `wsClient.delegate` = `RoomViewModel` ✓
- `RoomSyncManager` never receives messages — its `handleRawMessage` is never called.
- `RoomSyncManager.onPlayCommand/onPauseCommand/onSeekCommand` callbacks never fire.
- BUT — sync still works because `RoomViewModel.routeInbound` (line 225-274)
  handles sync messages directly via `syncEngine.handleSyncMessage(syncMsg)` (line 242).
- Chat also works via `RoomViewModel.routeInbound` line 248-256 → `messages.append`.

So **`RoomSyncManager` is essentially dead code** in the current architecture.
`RoomView` reads chat from `syncManager?.chatMessages ?? viewModel.messages`
(line 173) — since `syncManager.chatMessages` is always empty (delegate was
overwritten), it always falls back to `viewModel.messages`.

Additionally, **`wsClient.connectToServer(roomID:)` is called TWICE** — once by
`manager.connect()` (line 565) and once by `viewModel.joinRoomFlow()` (line 97).
The second call cancels the first via `socket?.cancel()` inside `connectInternal`
(line 183). Wasteful but functional.

**Recommendation:** Remove `RoomSyncManager` from `RoomView` entirely (let
`RoomViewModel` be the single delegate + chat source), OR remove the duplicate
`delegate = self` assignment in `joinRoomFlow` and let `RoomSyncManager` own
all routing. Pick one. The current dual-routing is confusing and the
`RoomSyncManager` callbacks at lines 555-563 are misleading dead code.

#### ⚠️ Sync Issue: `SyncEngine.seek(to:)` blocks guests from restoring position

**`SyncEngine.swift:189-202`**:
```swift
func seek(to time: TimeInterval) {
    guard isHost else { return }     // ← GUESTS CAN'T SEEK
    let clamped = max(0, min(time, duration))
    ...
}
```

**`RoomView.swift:93-96`** (in `.task`):
```swift
let savedPosition = UserDefaults.standard.double(forKey: "room_position_\(room.id)")
if savedPosition > 0 {
    viewModel.syncEngine.seek(to: savedPosition)   // ← no-op for guests
}
```

When a guest rejoins a room, the saved-position restore does nothing because
`seek(to:)` early-returns for non-hosts. This may be intentional (guests should
sync to host position, not their own), but then the saved-position logic for
guests is dead code. The `.task` should check `viewModel.isHost` before calling
`seek(to:)`.

#### ✅ Sync Issue: WebSocket actually connected (C1 fix verified)

`WebSocketClient.notifyConnectedIfNeeded()` (line 445) is called from:
- `handleReceiveResult` line 308 (first successful receive)
- The 250ms probe in `connectInternal` line 206-215 (proactive open-state inference)

Once `isConnected = true`, `flushPendingMessages()` runs and the send path is
unblocked. The `delegate` is set on line 94 of `RoomViewModel.joinRoomFlow`.
✓ C1 fix is real.

---

### 4. RAILWAY DEPLOYMENT CHECK — iOS-only repo

**Findings:**

| Item | Present? |
|------|----------|
| `server/` directory | ❌ No |
| `Dockerfile` | ❌ No |
| `docker-compose.yml` | ❌ No |
| `railway.toml` / `railway.json` | ❌ No |
| `package.json` / `go.mod` / `Cargo.toml` | ❌ No |
| `Procfile` | ❌ No |
| Backend source code (Node/Python/Go) | ❌ No |

**This is iOS-only.** The backend is hosted externally on Railway at
`https://xpkcakpkfewp-ofewk-pkv-production.up.railway.app` (hardcoded in
`APIClient.swift:44` and `WebSocketClient.swift:108`).

**Cannot deploy this repo to Railway as-is.** To deploy a Railway backend for
Plink, you would need a separate repo containing:

- WebSocket server (Node.js `ws` / `socket.io`, or Go gorilla/websocket)
- REST API for: `/api/auth/*`, `/api/rooms/*`, `/api/friends/*`, `/api/messages/dm/*`
- PostgreSQL database ( Railway Postgres addon)
- JWT auth with refresh tokens
- FCM push notification sending
- Apple receipt verification (App Store Server API)
- Yandex OAuth handler
- `apple-app-site-association` file hosting at `raveclone.app` for Universal
  Links (referenced in `Plink.entitlements:9`)

**What's also missing:**

- **No `apple-app-site-association` JSON file** in the repo (needed at
  `https://raveclone.app/.well-known/apple-app-site-association`).
- **No OpenAPI spec** documenting the backend contract — the iOS code is the
  only spec.
- **No backend tests**, no DB schema migration files.

The previous worklog notes `scripts/reset_database.sh` and `reset_database.sql`
exist — these are shell scripts for a Postgres DB reset, but they don't
constitute a deployable backend.

---

### 5. XCODE BUILD CHECK

#### `project.yml` paths — ✅ Correct
```yaml
sources:
  - path: Plink                  # ✓ correct (not RaveClone/)
    excludes:
      - "**/.DS_Store"
  - path: Plink/Resources/Info.plist
    buildPhase: none             # ✓ Info.plist is not a source file
resources:
  - path: Plink/Resources
```
Bundle ID `com.syncwatch.plink`, deployment target iOS 17.0, Swift 5.9, Xcode 16.0.

#### Source files location — ✅ All in `Plink/` subdirectory (verified via LS).

#### Assets structure — ❌ Missing AppIcon and colorsets

```
Assets.xcassets/
├── Contents.json
├── ServiceLogoDisney.imageset/
├── ServiceLogoDisneyWordmark.imageset/   ← unused (no .vkvideo case in VideoService enum)
├── ServiceLogoIvi.imageset/
├── ServiceLogoKinopoisk.imageset/
├── ServiceLogoKion.imageset/
├── ServiceLogoNetflix.imageset/
├── ServiceLogoOkko.imageset/
├── ServiceLogoPremier.imageset/
├── ServiceLogoRutube.imageset/
├── ServiceLogoSmotrim.imageset/
├── ServiceLogoStart.imageset/
├── ServiceLogoVk.imageset/
├── ServiceLogoVkvideoWordmark.imageset/  ← unused (no .vkvideo case in VideoService enum)
├── ServiceLogoWink.imageset/
└── ServiceLogoYoutube.imageset/
```

**Critical missing assets:**

1. **NO `AppIcon.appiconset`** — `project.yml:40` declares
   `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` but no `AppIcon.appiconset`
   exists. Xcode will emit a build warning ("warning: no image set named 'AppIcon'
   found") and the app will have **no icon** — instant App Store rejection.

2. **NO `AccentColor.colorset`** — minor, but iOS expects one.

3. **NO `raveBackground.colorset`** — `Info.plist:28` references `raveBackground`
   as the launch screen `UIColorName`:
   ```xml
   <key>UILaunchScreen</key>
   <dict>
       <key>UIColorName</key>
       <string>raveBackground</string>
   </dict>
   ```
   At runtime this name lookup fails silently and the launch screen renders with
   the default UIWindow background (likely black). Cosmetic but indicates
   incomplete project setup.

#### Info.plist keys — ✅ Mostly correct
- `CFBundleDisplayName`: "Плинк" ✓
- `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`,
  `NSPhotoLibraryUsageDescription`, `NSLocalNetworkUsageDescription` ✓ (C12 fix)
- `YANDEX_CLIENT_ID` = `$(YANDEX_CLIENT_ID)` ✓ (xcconfig injection)
- `PLINK_AI_API_KEY` = `$(PLINK_AI_API_KEY)` ✓
- `NSAppTransportSecurity.NSAllowsArbitraryLoads: false` ✓
- Missing: `CFBundleURLTypes` for custom-scheme deep links (only Universal
  Links are wired via entitlements). Acceptable if you only use Universal Links.
- Missing: `ITSAppUsesNonExemptEncryption` — App Store Connect will prompt for
  this on submission. Recommended to add `<false/>` since the app uses only
  standard HTTPS.

#### Entitlements — ⚠️ Inconsistent identifiers

`Plink.entitlements`:
```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:raveclone.app</string>     ← placeholder, not "plink.app"
</array>
<key>com.apple.developer.in-app-payments</key>
<array>
    <string>merchant.com.syncwatch.raveclone</string>     ← "raveclone" not "plink"
</array>
<key>aps-environment</key>
<string>development</string>     ← needs to be "production" before App Store submission
<key>com.apple.developer.background-modes</key>
<array>
    <string>audio</string>
    <string>voip</string>
    <string>remote-notification</string>
</array>
```

**Issues:**

1. **`applinks:raveclone.app`** — the project is renamed to Plink but the
   associated domain still says `raveclone.app`. Either register `raveclone.app`
   as the production domain, or change to `plink.app` and update the apple-app-
   site-association file accordingly. **The Universal Link handler in
   `RaveCloneApp.swift:131-163` will never fire** unless this domain hosts a
   valid apple-app-site-association file.

2. **`merchant.com.syncwatch.raveclone`** — inconsistent with the bundle ID
   `com.syncwatch.plink`. Apple merchant IDs are independent of bundle IDs so
   this can work, but the App Store Connect In-App Purchase configuration must
   reference this exact merchant ID. StoreManager.swift:35-37 product IDs are
   also `com.syncwatch.raveclone.premium.*` — same inconsistency. Recommend
   renaming all to `com.syncwatch.plink.*` for consistency, OR documenting that
   the merchant ID stays "raveclone" intentionally.

3. **`aps-environment: development`** — must be switched to `production` in a
   release build configuration. Xcode usually handles this automatically with
   separate entitlements files per config, but this single entitlements file
   will produce a development-only APN cert. App Store submission requires
   production entitlement.

---

### 6. ASSETS CHECK

#### Imagesets (14 total, all with Contents.json + PNG):

| Asset name | PNG file | Used by `VideoService.assetName`? |
|------------|----------|-----------------------------------|
| ServiceLogoYoutube | youtube.png | ✓ |
| ServiceLogoVk | vk.png | ✓ |
| ServiceLogoRutube | rutube.png | ✓ |
| ServiceLogoNetflix | netflix.png | ✓ |
| ServiceLogoDisney | disney.png | ✓ |
| ServiceLogoKinopoisk | kinopoisk.png | ✓ |
| ServiceLogoIvi | ivi.png | ✓ |
| ServiceLogoOkko | okko.png | ✓ |
| ServiceLogoWink | wink.png | ✓ |
| ServiceLogoStart | start.png | ✓ |
| ServiceLogoPremier | premier.png | ✓ |
| ServiceLogoSmotrim | smotrim.png | ✓ |
| ServiceLogoKion | kion.png | ✓ |
| ServiceLogoDisneyWordmark | disney.png | ❌ unused — no `.disneyWordmark` case in `VideoService` |
| ServiceLogoVkvideoWordmark | vkvideo.png | ❌ unused — no `.vkvideo` case in `VideoService` |

**All 13 referenced imagesets exist with valid Contents.json + PNG** (single-scale
universal, `preserves-vector-representation: true`). The two "Wordmark" sets
are dead assets — should be deleted or the `VideoService` enum should add cases
for them (probably not desired since the wordmark text is rendered via
`ServiceLogoView.wordmarkView` using `service.brandName`).

**Missing critical assets** (see Section 5):
- `AppIcon.appiconset` ❌
- `AccentColor.colorset` ❌ (recommended)
- `raveBackground.colorset` ❌ (referenced in Info.plist launch screen)

---

### 7. REMAINING BUGS — with file:line references

#### 🔴 Critical (compile-blocking / runtime-breaking)

| # | File:Line | Bug | Fix |
|---|-----------|-----|-----|
| B1 | `FriendManager.swift:34` + 4 call sites | `FriendManager()` called with no args but only `init(api: APIClient)` exists → **compile error** | Inject `@EnvironmentObject` or add `convenience init()` |
| B2 | `AIAssistantView.swift:283` | `self.errorMessage = ...` but no `errorMessage` property on the view → **compile error** | Add `@State private var errorMessage: String?` |
| B3 | `MainTabView.swift:332` | `let api = APIClient()` in `HomeTabContent.onAppear` creates unauthenticated client → all Home tab API calls 401 | Use `@EnvironmentObject var apiClient: APIClient` (already used by `RoomsTabContent`) |
| B4 | `HomeView.swift:110` | `ProfileView(viewModel: ProfileViewModel(authService: AuthService(api: APIClient())), ...)` creates unauthenticated client → profile fails to load | Inject from environment |
| B5 | `Assets.xcassets` | No `AppIcon.appiconset` — app will have no icon, App Store rejection | Add AppIcon.appiconset with all required sizes (1024, 180, 120, 87, 80, 60, 40, 29, 20) |
| B6 | `Info.plist:28` + assets | `raveBackground` UIColorName referenced but no `raveBackground.colorset` in assets → launch screen renders default | Add colorset OR remove the `UIColorName` reference |
| B7 | `Plink.entitlements:9` | `applinks:raveclone.app` — placeholder domain, Universal Links won't work until real domain hosts apple-app-site-association | Replace with actual domain |
| B8 | `Plink.entitlements:19` | `aps-environment: development` — wrong for App Store release | Use build-config-specific entitlements with `production` for Release |

#### 🟠 High (functional bugs)

| # | File:Line | Bug |
|---|-----------|-----|
| H1 | `RoomSetupView.swift:287-347` | `createRoom()` builds local `Room` but never calls `RoomService.createRoom()` REST endpoint — room is local-only, never persists server-side, never appears in "Мои комнаты" on next launch |
| H2 | `RoomSetupView.swift:22` + line 327 | `privacy: RoomPrivacy` state is selected in UI but NOT passed to `Room(...)` initializer — Room model has no `privacy` field at all. User-selected privacy is silently dropped. |
| H3 | `RoomSetupView.swift:23` | `maxParticipants = 10` initial value doesn't match either free (4) or premium (50) constraint. Stepper is `in: 2...(isPremium ? 50 : 4)` — initial 10 violates the free-user range, will visually clamp on first interaction but the `maxParticipants` field stays 10 until user moves the stepper. |
| H4 | `VideoContainerView.swift:71-75` | `VideoPlayerRepresentable(url:isPlaying:currentTime:)` does NOT pass `sharedPlayer` from SyncEngine — defaults to `nil`. The H3 "unified AVPlayer" fix mentioned in SyncEngine.swift:55 comment is **incomplete** — `SyncEngine.player` exists as `private(set) var player: AVPlayer?` but `VideoContainerView` never reads it. Result: TWO AVPlayer instances are created (SyncEngine's invisible one + VideoContainerView's visible one), causing visual desync. |
| H5 | `RoomView.swift:488-505` | `sendMessage()` uses hardcoded `senderID: "current_user"` and `senderName: "You"` instead of the resolved `currentUserId` from `setupViewModel()`. Server can't identify the sender; chat messages from this client appear with wrong ID. |
| H6 | `RoomView.swift:476` | Same issue in `triggerReaction` — `senderId: "current_user"` hardcoded. |
| H7 | `RoomView.swift:513-515` | `setupViewModel()` creates a NEW `WebSocketClient`, `RoomService`, `AuthService` per RoomView appearance instead of reusing the shared instances from `RaveCloneApp`. Comment claims "FIX C7 uses shared APIClient" but only APIClient is shared — the other 3 services are fresh (with their own state, observers, etc.). |
| H8 | `RoomView.swift:565` + `RoomViewModel.swift:94` | `wsClient.delegate` is set to RoomSyncManager in `setupViewModel`, then OVERWRITTEN by `RoomViewModel` in `joinRoomFlow`. RoomSyncManager's callbacks (lines 555-563) are dead code. |
| H9 | `RoomCreationView.swift:10` | `var friendManager: FriendManager = FriendManager()` — same compile error as B1, plus the local instance won't share state with the app's shared FriendManager. |
| H10 | `RoomCreationView.swift:474-484` | `demoStreamURL` fallback is unreachable: the `nextStep()` validation (line 452-455) rejects empty URLs before `createRoom()` is called, so the `if effectiveURL.isEmpty { demoStreamURL }` branch is dead code. |
| H11 | `SyncEngine.swift:189-202` | `seek(to:)` guards `isHost` — guests calling `seek(to:)` is a no-op. `RoomView.swift:95` calls `syncEngine.seek(to: savedPosition)` unconditionally on rejoin; for guests this is silently dropped. |
| H12 | `FriendsView.swift:62` | `ShareManager.shareRoom(roomID: "current_user", ...)` — hardcoded "current_user" instead of real user ID. Invite link will be broken. |
| H13 | `StoreManager.swift:189 + 226` | Two `checkVerified` methods (static `T?` + instance `T`) with same name — confusing, instance version is dead code. Cosmetic. |
| H14 | `MainTabView.swift:43` | `AIAssistantView()` is constructed as a TabView child but `AIAssistantView` doesn't have an `init()` accepting parameters and uses default init. This works because `AIAssistantView` has no required init params. But the AI tab is created without any DI — fine since `AIService.shared` is a singleton. |

#### 🟡 Medium (UX / data issues)

| # | File:Line | Bug |
|---|-----------|-----|
| M1 | `RoomView.swift:144` | Share sheet URL is `https://raveclone.com/join/\(room.code)` — inconsistent with `raveclone.app` in entitlements. Which domain is real? |
| M2 | `APIClient.swift:44`, `WebSocketClient.swift:108` | Backend URLs hardcoded as string defaults. Should be configurable via xcconfig for dev/staging/prod. |
| M3 | `MainTabView.swift:332` | Home tab creates fresh `APIClient()` instead of using `@EnvironmentObject` — inconsistent with `RoomsTabContent` (line 99) which uses the shared one. |
| M4 | `WebSocketClient.swift:191` | `request.setValue("raveclone://ios", forHTTPHeaderField: "Origin")` — Origin should be `plink://ios` for branding. Cosmetic. |
| M5 | `VideoService.swift:147-176` | `RoomPrivacy.icon` is defined on `RoomPrivacy` enum but `RoomSetupView.privacyIcon(_:)` (line 239) duplicates the logic with different icons (`globe` vs `person.2.fill`). Inconsistent. |
| M6 | `PremiumStatusManager.swift:115-121` | `persist()` writes `selectedNickStyle`/`selectedAvatarBorder`/`selectedRoomTheme` even when user is non-premium — wasteful but harmless. |
| M7 | `AIAssistantView.swift:143-148` | Quick prompts are hardcoded Russian strings, not localized via `LocalizationManager`. L1 fix incomplete. |
| M8 | `MainTabView.swift:33-61` | Tab labels are hardcoded Russian ("Главная", "Комнаты", "ИИ", "Друзья", "Настройки") — not localized. |
| M9 | `RoomSetupView.swift:349-352` | `generateRoomCode()` uses `chars.randomElement()!` — force-unwrap on a non-empty static string is safe, but `String((0..<6).map { _ in chars.randomElement()! })` is inefficient. Use `String((0..<6).compactMap { _ in chars.randomElement() })`. |
| M10 | `RoomView.swift:472-475` | `UIScreen.main.bounds` is deprecated on iOS 16+ for multi-scene apps. Use `geo.size` from the GeometryReader at line 55. |

#### 🟢 Low (cosmetic / dead code)

| # | File:Line | Bug |
|---|-----------|-----|
| L1 | `RaveCloneApp.swift` filename | File is named `RaveCloneApp.swift` but the struct is `PlinkApp` (line 8). Confusing rename leftover. |
| L2 | `MainTabView.swift:9` | Comment "Receive shared services from RaveCloneApp via EnvironmentObject" — should say "PlinkApp". |
| L3 | `Assets.xcassets/ServiceLogoDisneyWordmark.imageset` | Unused — no `.disneyWordmark` case in `VideoService`. |
| L4 | `Assets.xcassets/ServiceLogoVkvideoWordmark.imageset` | Unused — no `.vkvideo` case in `VideoService`. |
| L5 | `RoomSyncManager.swift` entire file (~488 lines) | Effectively dead code due to H8. Either fix the architecture or delete. |
| L6 | `RoomCreationView.swift:10` | `friendManager` is declared but only used for invite step display — and never receives data because it's a fresh unauthenticated instance. |
| L7 | `SyncEngine.swift:425` | `isStatePulse = mediaTimeDelta < Constants.stateBroadcastInterval` — compares media-time-delta (seconds) against `stateBroadcastInterval` (also seconds), which is conceptually fragile but works in practice. |
| L8 | `WebSocketClient.swift:488-499` | `isConnectedBridge` nonisolated var is dead code — never called from anywhere in the project. |
| L9 | `StoreManager.swift:226-233` | Instance `checkVerified` is dead code (only the static version at line 189 is called). |
| L10 | Various | Many hardcoded Russian strings bypass `LocalizationManager.shared` (L1 from previous audit, still incomplete). |

---

### 8. QUALITY ASSESSMENT

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| **Code quality** | **6/10** | Generally well-structured Swift with good use of actors, protocols, and DI. But two compile errors slipped through (B1, B2), the `RoomSyncManager` is dead code (H8), and `VideoContainerView` doesn't pass `sharedPlayer` despite the comment claiming it does (H4). Comments are extensive but sometimes contradict the code. |
| **Feature completeness** | **7/10** | All major features present: auth, rooms, sync, chat, DM, friends, AI, premium IAP, ads, reactions, voice chat. BUT room creation doesn't persist server-side (H1), privacy setting is dropped (H2), and several screens use unauthenticated clients (B3, B4). |
| **Design quality** | **8/10** | Cohesive "Bioluminescent Dark Premium" aesthetic with consistent cyan/teal/emerald palette. Custom toggles, glass cards, animated backgrounds, premium message sparks. Apple ID-style Settings is well-executed. Loses points for hardcoded Russian strings (no i18n) and inconsistent icon usage (M5). |
| **Security** | **7/10** | JWT in Keychain (C2 fixed). Auth refresh logic is robust (doesn't force signout on transient errors). Public auth endpoints don't carry stale tokens (AUTH BUG fix). BUT: `raveclone.app` entitlement placeholder (B7), `aps-environment: development` for release (B8), and AI API key stored in Info.plist (acceptable but visible in IPA). |
| **Performance** | **7/10** | Latency-compensated sync with RTT estimation. Display-link throttled to 4 FPS for Ambilight. LazyVStack/LazyVGrid used appropriately. BUT: two AVPlayer instances (H4) doubles decode load, `RoomView.setupViewModel` creates fresh WS/RoomService/Auth per appearance, and `RoomSyncManager` registers background observers that may fire on dead instances. |
| **App Store readiness** | **3/10** | Will not pass review: no AppIcon (B5), placeholder associated domain (B7), development APN environment (B8), no `ITSAppUsesNonExemptEncryption` key. Privacy policy URL not configured. Missing TestFlight metadata. Also two compile errors (B1, B2) prevent building an IPA at all. |

**Overall: 6.3/10** — Promising foundation with strong design and architecture,
but the project is **not currently compilable** and has several App Store
blockers that must be addressed before submission.

---

### 9. COMPETITOR COMPARISON — Plink vs Rave vs Hearo

| Feature | **Plink** | **Rave** | **Hearo** |
|---------|-----------|----------|-----------|
| **iOS native app** | ✅ SwiftUI iOS 17+ | ✅ Native | ✅ Native |
| **Co-watch YouTube** | ✅ AVPlayer + WebView | ✅ Native | ✅ Native |
| **Co-watch Netflix/Disney+** | ✅ WebView with auth | ❌ Not supported | ⚠️ Limited |
| **Russian cinema (Kinopoisk/Okko/Ivi)** | ✅ 8 services with logos | ❌ | ❌ |
| **Voice chat in room** | ✅ WebRTC mesh (VoiceChatService) | ✅ WebRTC | ✅ WebRTC |
| **Text chat** | ✅ Room + DM | ✅ | ✅ |
| **Friends system** | ✅ Search + requests + DM | ⚠️ Limited | ⚠️ Limited |
| **AI recommendations** | ✅ OpenRouter (Claude 3.5 Sonnet / Gemini Flash) | ❌ | ❌ |
| **In-app purchases** | ✅ StoreKit 2 (monthly/quarterly/yearly) | ✅ | ✅ |
| **Synchronized ads** | ✅ AdSessionManager (15-25 min intervals) | ✅ | ❌ |
| **Premium tier** | ✅ Ad-free + 50 participants + customization | ✅ | ⚠️ |
| **Latency compensation** | ✅ Server-time sync + RTT + drift correction | ⚠️ Basic | ⚠️ Basic |
| **Universal Links (deep join)** | ⚠️ Wired but placeholder domain | ✅ | ✅ |
| **Push notifications** | ⚠️ FCM wired but aps-environment=dev | ✅ | ✅ |
| **Reactions (emoji overlay)** | ✅ SpriteKit + Danmaku | ✅ | ⚠️ Basic |
| **Landscape + portrait layouts** | ✅ Full adaptive | ✅ | ✅ |
| **Background modes (audio/voip)** | ✅ Declared in entitlements | ✅ | ✅ |
| **Screen capture / share** | ⚠️ Service exists, not wired into RoomView | ✅ | ✅ |
| **Admin panel** | ✅ AdminPanelView (admin role only) | ❌ | ❌ |
| **User blocking / moderation** | ✅ UserBlockManager + room filtering | ⚠️ Report only | ⚠️ Report only |
| **Localization** | ⚠️ Russian + partial English + partial Chinese | ✅ Multi-lang | ✅ Multi-lang |
| **Public room discovery** | ✅ "Мои комнаты" + "Общедоступные" | ✅ | ✅ |
| **Design polish** | ✅ Bioluminescent glass aesthetic | ✅ Neon/dark | ⚠️ Basic |
| **OpenRouter AI integration** | ✅ UNIQUE — no competitor has this | ❌ | ❌ |
| **Russian cinema support** | ✅ UNIQUE — 8 RU streaming services | ❌ | ❌ |
| **User short ID for friend search** | ✅ UNIQUE — #ef1234567890 format | ❌ | ❌ |

#### What Plink does better:

1. **AI assistant** — real LLM streaming (Claude 3.5 Sonnet) for film
   recommendations, locked to film-domain queries. Neither Rave nor Hearo has
   any AI.
2. **Russian cinema catalog** — Kinopoisk, Ivi, Okko, Wink, Start, Premier,
   Smotrim, KION. Rave and Hearo are YouTube/Netflix only.
3. **Latency compensation** — proper server-time sync via ping/pong, RTT
   smoothing, drift detection with soft + hard correction thresholds. Rave's
   sync is naive.
4. **Premium customization** — nick styles (neon/gold/fire/ice), avatar borders,
   room themes. Rave has none of this.
5. **Design cohesion** — single bioluminescent palette across all screens,
   glass-morphism, animated background. Rave is more utilitarian.
6. **Admin tools** — built-in admin panel + user blocking + room reporting.
7. **Short user IDs** — last-8-chars UUID display for friend search. Solves a
   real UX problem Rave doesn't address.

#### What Plink is missing:

1. **Compilable code** — Rave and Hearo ship. Plink currently has 2 compile
   errors.
2. **AppIcon** — Rave and Hearo have proper icons. Plink's asset catalog is
   missing AppIcon.appiconset.
3. **Real Universal Links domain** — Plink uses placeholder `raveclone.app`;
   Rave uses real `rave.app`.
4. **Screen share** — `ScreenCaptureService.swift` exists in Plink but is NOT
   wired into RoomView. Rave has working screen share.
5. **Multi-language** — Plink has hardcoded Russian everywhere. Rave ships 10+
   languages.
6. **Web/desktop client** — Rave has a web app; Plink is iOS-only.
7. **Stable backend repo** — Plink's backend lives elsewhere (not in this
   repo), making deployment/reproducibility harder.
8. **CAM (camera) in room** — Rave supports camera-on; Plink has voice but no
   camera tiles in RoomView.
9. **Content search within service** — `YouTubeSearchService` exists but
   `YouTubeSearchView` is not reachable from the main flow.
10. **Watch history persistence** — `WatchHistory` model exists but isn't
    populated from room sessions.

---

### 10. TOP 10 SUGGESTED IMPROVEMENTS

#### Priority 1 — Make it build and submit

1. **Fix the two compile errors (B1, B2).** Without these, nothing else matters.
   - Add `@State private var errorMessage: String?` to `AIAssistantView`.
   - Inject `FriendManager` via `@EnvironmentObject` in all 4 call sites, OR
     add `convenience init() { self.init(api: APIClient()) }` to
     `FriendManager` as a minimal patch.

2. **Add `AppIcon.appiconset` to `Assets.xcassets`** with all required sizes
   (1024×1024 store, 180/120/87/80/60/40/29/20 device sizes). Without an icon,
   App Store review is instant rejection.

3. **Fix entitlements for release:**
   - Replace `applinks:raveclone.app` with your real registered domain.
   - Add a Release-config entitlements file with `aps-environment: production`.
   - Host `apple-app-site-association` JSON at
     `https://<your-domain>/.well-known/apple-app-site-association`.

#### Priority 2 — Make features actually work end-to-end

4. **Wire `RoomSetupView.createRoom()` to the REST API.** Currently it builds a
   local `Room` and never calls `RoomService.createRoom()` (H1). The room
   won't appear in "Мои комнаты" on next launch because the server doesn't
   know about it. Add:
   ```swift
   Task {
       do {
           let created = try await roomService.createRoom(CreateRoomRequest(
               name: name, maxParticipants: maxParticipants, mediaItem: mediaItem))
           onRoomCreated(created)
       } catch { errorMessage = error.localizedDescription }
   }
   ```

5. **Add `privacy` field to `Room` model and pass it through.** Currently the
   privacy selector in `RoomSetupView` is silently dropped (H2). Add
   `let privacy: RoomPrivacy` to `Room`, include it in `CreateRoomRequest`,
   and have the backend filter discovery by privacy.

6. **Pass `sharedPlayer` from SyncEngine to VideoPlayerRepresentable (H4).**
   The "FIX H3" comment claims this is done, but `VideoContainerView.swift:71`
   doesn't pass the parameter. Either pass it:
   ```swift
   VideoPlayerRepresentable(
       url: url, isPlaying: isPlaying, currentTime: currentTime,
       sharedPlayer: viewModel.syncEngine.player
   )
   ```
   …or remove the `sharedPlayer` parameter entirely if you don't want to wire
   it through. The current state (parameter exists, defaults to nil, never
   passed) is the worst of both worlds — two AVPlayers, visual desync.

7. **Use real `currentUserId` in `RoomView.sendMessage()` and `triggerReaction()` (H5, H6).**
   Replace `senderID: "current_user"` with the resolved `currentUserId` from
   `setupViewModel()`. The server can't attribute chat messages or reactions
   to the right user otherwise.

#### Priority 3 — Architecture cleanup

8. **Delete `RoomSyncManager` OR remove its delegate assignment.** The current
   architecture has both `RoomViewModel` and `RoomSyncManager` setting
   themselves as `wsClient.delegate` — only the last assignment wins, so
   `RoomSyncManager` is dead code (H8). Pick one routing path:
   - **Option A (recommended):** Delete `RoomSyncManager`, let `RoomViewModel`
     own all routing (it already does via `routeInbound`).
   - **Option B:** Remove `wsClient.delegate = self` from
     `RoomViewModel.joinRoomFlow()`, let `RoomSyncManager` be the sole
     delegate, and route sync messages from `RoomSyncManager.handleSyncMessage`
     into `RoomViewModel.syncEngine.handleSyncMessage`.

9. **Centralize service injection.** `MainTabView.HomeTabContent` (line 332)
   and `HomeView` profile sheet (line 110) create fresh
   `APIClient()`/`AuthService()`/`RoomService()` instances that are
   unauthenticated (B3, B4). All tab contents should use
   `@EnvironmentObject var apiClient: APIClient` like `RoomsTabContent` does.
   Consider also injecting `AuthService` and `RoomService` via EnvironmentObject
   or a DI container.

10. **Make backend URLs configurable via xcconfig.** `APIClient.swift:44` and
    `WebSocketClient.swift:108` hardcode the Railway URL. Add to `Info.plist`:
    ```xml
    <key>PLINK_API_BASE_URL</key>
    <string>$(PLINK_API_BASE_URL)</string>
    <key>PLINK_WS_BASE_URL</key>
    <string>$(PLINK_WS_BASE_URL)</string>
    ```
    Then read at runtime. Allows dev/staging/prod builds without code changes.

---

### FINAL VERDICT

**Buildable today?** ❌ No — two compile errors (B1, B2) block the build.

**App Store ready?** ❌ No — missing AppIcon (B5), placeholder Universal
Links domain (B7), development APN environment (B8), and the compile errors.

**Estimated time to App Store submission:**
- Fix B1 + B2 (compile errors): **2 hours**
- Add AppIcon + colorsets + entitlements cleanup: **2 hours**
- Fix H1 (room creation server persistence) + H2 (privacy field) + H4
  (sharedPlayer) + H5/H6 (senderID): **1 day**
- Wire `apple-app-site-association` on backend + Universal Links testing: **1 day**
- Full regression test of all 10 feature paths: **1 day**

**Total: ~3-4 working days to go from "doesn't compile" to "TestFlight-ready".**

The architecture is sound, the design is polished, the sync engine is
genuinely sophisticated (latency compensation with RTT estimation is more
advanced than Rave's), and the AI integration is unique. The problems are
all "last-mile wiring" issues — features built 90% of the way but with the
final connection missing. Once those are fixed, Plink is a credible
competitor with several features (RU cinema support, AI assistant, premium
customization) that Rave and Hearo don't have.

---

*End of Task FULL-AUDIT-FINAL report.*
