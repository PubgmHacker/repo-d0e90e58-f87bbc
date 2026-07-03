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
