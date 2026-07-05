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

    /// Локально выбранная аватарка из галереи (кэшируется).
    /// Синхронизируется через shared-синглтон между всеми экранами.
    var avatarImage: UIImage? {
        get { Self.sharedAvatar }
        set { Self.sharedAvatar = newValue }
    }

    /// Общий аватар для всех ProfileViewModel-инстансов (профиль + шторка настроек).
    static var sharedAvatar: UIImage? {
        didSet { Self.notifyAvatarChange() }
    }

    /// Уведомляет все инстансы об изменении аватара.
    private static func notifyAvatarChange() {
        // Триггерим перерисовку через NotificationCenter
        NotificationCenter.default.post(name: Self.avatarChangedNotification, object: nil)
    }
    static let avatarChangedNotification = Notification.Name("plink_avatar_changed")

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
    func saveAvatar(_ image: UIImage) {
        Self.sharedAvatar = image
        // Сохраняем в Documents directory
        if let data = image.jpegData(compressionQuality: 0.8) {
            let url = avatarFileURL
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Загружает ранее сохранённую аватарку с диска в shared-кэш.
    func loadAvatarFromDisk() {
        if let existing = Self.sharedAvatar { return }  // уже загружено
        let url = avatarFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return }
        Self.sharedAvatar = img
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
