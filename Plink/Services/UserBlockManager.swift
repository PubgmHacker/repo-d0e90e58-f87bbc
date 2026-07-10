import Foundation
import Combine

// MARK: - User Block Manager (Блок 1 — Apple UGC: модерация контента)
/// Локальное управление блокировкой пользователей и жалобами.
///
/// Apple App Store требует, чтобы любое UGC-приложение предоставляло:
/// - Возможность пожаловаться на контент (Report).
/// - Возможность заблокировать пользователя (Block).
/// - Локальную фильтрацию контента от заблокированных юзеров.
///
/// Этот менеджер:
/// - Хранит список заблокированных ID локально (UserDefaults).
/// - Предоставляет фильтрацию сообщений/комнат в реальном времени.
/// - Синхронизирует блокировки с бэкендом (через callback `onBlockChanged`).
@MainActor
final class UserBlockManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var blockedUserIds: Set<String> = []

    // MARK: - Callbacks

    /// Вызывается при изменении списка блокировок (для синхронизации с бэкендом).
    var onBlockChanged: ((String, Bool) -> Void)?

    // MARK: - Storage

    private let defaults = UserDefaults.standard
    private let storageKey = "rave_blocked_users"

    // MARK: - Init

    init() {
        loadBlockedUsers()
    }

    // MARK: - Block / Unblock

    func blockUser(_ userId: String) {
        blockedUserIds.insert(userId)
        persist()
        onBlockChanged?(userId, true)
    }

    func unblockUser(_ userId: String) {
        blockedUserIds.remove(userId)
        persist()
        onBlockChanged?(userId, false)
    }

    func toggleBlock(_ userId: String) {
        if blockedUserIds.contains(userId) {
            unblockUser(userId)
        } else {
            blockUser(userId)
        }
    }

    func isBlocked(_ userId: String) -> Bool {
        blockedUserIds.contains(userId)
    }

    // MARK: - Filtering

    /// Фильтрует сообщения чата, убирая те, что от заблокированных юзеров.
    func filterMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !blockedUserIds.isEmpty else { return messages }
        return messages.filter { !blockedUserIds.contains($0.senderID) }
    }

    /// Фильтрует комнаты, убирая те, где хост заблокирован.
    func filterRooms(_ rooms: [Room]) -> [Room] {
        guard !blockedUserIds.isEmpty else { return rooms }
        return rooms.filter { !blockedUserIds.contains($0.hostID) }
    }

    // MARK: - Report (отправка жалобы на бэкенд)

    /// Отправляет жалобу на пользователя. Реальная отправка через callback.
    func reportUser(_ userId: String, reason: String, onResult: @escaping (Result<Void, Error>) -> Void) {
        // В продакшене здесь POST /reports { targetUserId, reason }
        // Пока — имитация успешной отправки.
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            onResult(.success(()))
        }
    }

    /// Отправляет жалобу на комнату.
    func reportRoom(_ roomId: String, reason: String, onResult: @escaping (Result<Void, Error>) -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            onResult(.success(()))
        }
    }

    // MARK: - Persistence

    private func persist() {
        let array = Array(blockedUserIds)
        defaults.set(array, forKey: storageKey)
    }

    private func loadBlockedUsers() {
        if let array = defaults.array(forKey: storageKey) as? [String] {
            blockedUserIds = Set(array)
        }
    }
}

// MARK: - Report Reason (типизированные причины жалобы)
enum ReportReason: String, CaseIterable, Identifiable {
    case spam = "Спам"
    case harassment = "Оскорбления / травля"
    case inappropriateContent = "Неподходящий контент"
    case copyright = "Нарушение авторских прав (DMCA)"
    case other = "Другое"

    var id: String { rawValue }

    /// API-код причины для бэкенда.
    var apiCode: String {
        switch self {
        case .spam: return "spam"
        case .harassment: return "harassment"
        case .inappropriateContent: return "inappropriate"
        case .copyright: return "copyright"
        case .other: return "other"
        }
    }
}
