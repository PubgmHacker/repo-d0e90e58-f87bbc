import Foundation
import UIKit

// MARK: - Profile View Model (Блок 2 — Профиль + История просмотров)
@MainActor
@Observable
final class ProfileViewModel {

    // MARK: - State

    var user: User?
    var isLoading = false
    var errorMessage: String?

    /// 🔧 FIX: Локально выбранная аватарка из галереи.
    /// Раньше была computed property от static var — @Observable не отслеживает
    /// static storage, поэтому SwiftUI не перерисовывал экраны при смене аватара.
    /// Теперь это stored instance property — @Observable отслеживает её напрямую.
    /// Синхронизация между инстансами (ProfileView ↔ SettingsView) идёт через
    /// NotificationCenter: при saveAvatar() все инстансы получают уведомление и
    /// обновляют свой instance avatarImage.
    var avatarImage: UIImage?

    /// Общий аватар для всех ProfileViewModel-инстансов (профиль + шторка настроек).
    /// При изменении постит notification — все инстансы подтягивают новое значение.
    static var sharedAvatar: UIImage? {
        didSet { Self.notifyAvatarChange() }
    }

    /// Уведомляет все инстансы об изменении аватара.
    private static func notifyAvatarChange() {
        NotificationCenter.default.post(name: Self.avatarChangedNotification, object: nil)
    }
    static let avatarChangedNotification = Notification.Name("plink_avatar_changed")

    /// 🔧 FIX: Подписка на смену аватара другим инстансом (например, когда юзер
    /// меняет фото в ProfileView — SettingsView тоже должен обновиться немедленно).
    ///
    /// 🔧 SWIFT 6 strict mode: `nonisolated(unsafe)` required for mutable var.
    /// `nonisolated` alone is rejected ("cannot be applied to mutable stored
    /// properties"). The Swift 5 warning "has no effect" was misleading.
    /// We keep `nonisolated(unsafe)` — it's the explicit opt-out for mutable
    /// state accessed from nonisolated deinit. The observer token is only
    /// mutated in init (main actor) and removed in nonisolated deinit.
    /// NotificationCenter.removeObserver is internally thread-safe.
    nonisolated(unsafe) private var avatarObserver: NSObjectProtocol?

    // История просмотров (Блок 2)
    var history: [WatchHistoryItem] {
        historyManager.history
    }

    /// Выбранный медиа-итем для пересоздания комнаты («Посмотреть снова»).
    var rewatchMedia: MediaItem?

    var displayName: String {
        user?.displayName ?? "Гость"
    }

    var email: String {
        user?.email ?? ""
    }

    var username: String {
        user?.username ?? ""
    }

    var avatarURL: String? {
        user?.avatarURL
    }

    // MARK: - Stats (реальные данные из services)

    var roomsJoined: Int { history.count }
    var hoursWatched: Int {
        // Суммарная реально досмотренная длительность (watchedDuration в секундах).
        let totalSeconds = history.reduce(0.0) { $0 + $1.watchedDuration }
        return Int((totalSeconds / 3600).rounded())
    }
    var friendsCount: Int { 0 }  // Будет populated из FriendManager при интеграции

    // MARK: - Services

    let authService: AuthServiceProtocol
    private let historyManager = WatchHistoryManager()

    // MARK: - Init

    init(authService: AuthServiceProtocol) {
        self.authService = authService
        // 🔧 FIX: Subscribe to avatar-changed notifications from OTHER instances.
        // When user changes photo in ProfileView, SettingsView's viewModel receives
        // this notification and updates its own instance avatarImage → @Observable
        // triggers re-render → avatar updates IMMEDIATELY, no re-entry needed.
        avatarObserver = NotificationCenter.default.addObserver(
            forName: Self.avatarChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Sync from the shared static into this instance's observable property.
                if self.avatarImage !== Self.sharedAvatar {
                    self.avatarImage = Self.sharedAvatar
                }
            }
        }
    }

    nonisolated deinit {
        // 🔧 FIX: Remove the notification observer to avoid leaks / zombie callbacks.
        // nonisolated to match RoomViewModel pattern — safe for Swift 6 strict concurrency.
        if let avatarObserver {
            NotificationCenter.default.removeObserver(avatarObserver)
        }
    }

    func loadUser() async {
        isLoading = true
        // 🔧 Pack v3: Загружаем с сервера (GET /users/me), не из локального кэша
        do {
            let fresh: User = try await authService.fetchCurrentUser()
            user = fresh
            // Обновляем локальный кэш в AuthService
            authService.updateCachedUser(fresh)
        } catch {
            // Fallback на локальный кэш
            user = await authService.currentUser()
        }
        loadAvatarFromDisk()
        isLoading = false
    }

    // MARK: - Avatar (загрузка из галереи)

    private let avatarCacheKey = "local_avatar_image"

    /// Сохраняет выбранное из галереи фото как локальную аватарку.
    /// 🔧 FIX: Теперь обновляет instance avatarImage немедленно → @Observable
    /// перерисовывает текущий экран сразу, без перезахода. Другие инстансы
    /// подтянутся через notification (см. init).
    func saveAvatar(_ image: UIImage) {
        Self.sharedAvatar = image          // posts notification via didSet
        avatarImage = image                 // immediate instance-level update
        // Сохраняем в Documents directory
        if let data = image.jpegData(compressionQuality: 0.8) {
            let url = avatarFileURL
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Загружает ранее сохранённую аватарку с диска в instance + shared-кэш.
    /// 🔧 FIX: Теперь пишет и в instance avatarImage, и в static sharedAvatar.
    func loadAvatarFromDisk() {
        // Сначала синхронизируемся со shared-кэшем (мог быть загружен другим инстансом)
        if let shared = Self.sharedAvatar, avatarImage == nil {
            avatarImage = shared
            return
        }
        guard avatarImage == nil, Self.sharedAvatar == nil else { return }
        let url = avatarFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return }
        Self.sharedAvatar = img    // posts notification (но текущий инстанс уже обновится ниже)
        avatarImage = img
    }

    private var avatarFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("avatar.jpg")
    }

    // MARK: - History Actions (Блок 2)

    func removeHistoryItem(_ item: WatchHistoryItem) {
        historyManager.remove(item)
    }

    func clearHistory() {
        historyManager.clearAll()
    }

    /// Открывает создание новой комнаты с этим видео.
    func rewatch(_ item: WatchHistoryItem) {
        rewatchMedia = item.mediaItem
    }

    // MARK: - Account

    func updateUsername(_ newName: String) async {
        guard let current = user else { return }
        // 🔧 Pack v3: Отправляем на сервер (PATCH /users/me)
        do {
            let updated: User = try await authService.updateProfile(username: newName, avatarURL: current.avatarURL)
            user = updated
            authService.updateCachedUser(updated)
        } catch {
            // Fallback: локальное обновление
            user = User(id: current.id, username: newName, email: current.email,
                        avatarURL: current.avatarURL, isOnline: current.isOnline,
                        isPremium: current.isPremium, role: current.role, createdAt: current.createdAt)
            errorMessage = "Не удалось сохранить на сервере: \(error.localizedDescription)"
        }
    }

    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
