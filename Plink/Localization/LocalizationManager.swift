import Foundation
import SwiftUI
import Combine

// MARK: - App Language
/// Поддерживаемые языки приложения. Переключаются в рантайме (не системно).
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case russian = "ru"
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    /// Название языка на самом языке (для переключателя).
    var nativeName: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    /// English name of the language.
    var englishName: String {
        switch self {
        case .russian: return "Russian"
        case .english: return "English"
        case .chinese: return "Chinese"
        }
    }

    /// Флаг для иконки.
    var flag: String {
        switch self {
        case .russian: return "🇷🇺"
        case .english: return "🇬🇧"
        case .chinese: return "🇨🇳"
        }
    }
}

// MARK: - Localization Manager
/// Менеджер локализации с переключением языка в рантайме.
/// Хранит выбор в UserDefaults, транслирует изменения через objectWillChange.
@MainActor
final class LocalizationManager: ObservableObject {

    static let shared = LocalizationManager()

    /// Текущий язык (публикуется → UI обновляется автоматически).
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "plink_app_language"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.russian.rawValue
        currentLanguage = AppLanguage(rawValue: raw) ?? .russian
    }

    /// Nonisolated доступ к текущему языку для use-case'ов вне MainActor
    /// (например, вычисляемые свойства enum'ов). Читает напрямую из UserDefaults.
    static var sharedSafe: LanguageReader { LanguageReader() }

    /// Локализованная строка по ключу.
    func string(_ key: L10n.Key) -> String {
        L10n.table[key]?[currentLanguage] ?? key.rawValue
    }
}

/// Thread-safe read-only доступ к выбранному языку.
struct LanguageReader {
    var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "plink_app_language") ?? AppLanguage.russian.rawValue
        return AppLanguage(rawValue: raw) ?? .russian
    }
}

// MARK: - L10n (Strings Table)
/// Все строки приложения в одном месте. Добавлять новые — сюда.
enum L10n {

    enum Key: String {
        // App / Brand
        case appName = "app.name"
        case appTagline = "app.tagline"

        // Common
        case cancel = "common.cancel"
        case done = "common.done"
        case back = "common.back"
        case save = "common.save"
        case delete = "common.delete"
        case error = "common.error"
        case loading = "common.loading"
        case search = "common.search"

        // Login
        case loginTitle = "login.title"
        case loginTagline = "login.tagline"
        case loginEmail = "login.email"
        case loginPassword = "login.password"
        case loginUsername = "login.username"
        case loginSignIn = "login.signIn"
        case loginSigningIn = "login.signingIn"
        case loginSignUp = "login.signUp"
        case loginDontHaveAccount = "login.dontHaveAccount"
        case loginAlreadyHaveAccount = "login.alreadyHaveAccount"
        case loginContinueWith = "login.continueWith"
        case loginConnecting = "login.connecting"
        case loginTerms = "login.terms"
        case loginCreateAccount = "login.createAccount"
        case loginJoinParty = "login.joinParty"

        // Home / Discover
        case homeDiscover = "home.discover"
        case homeWatchingNow = "home.watchingNow"
        case homeCreateRoom = "home.createRoom"
        case homeCreateRoomSubtitle = "home.createRoomSubtitle"
        case homeSearchRooms = "home.searchRooms"
        case homePublicRooms = "home.publicRooms"
        case homeTrending = "home.trending"
        case homeNoRooms = "home.noRooms"
        case homeLoadingRooms = "home.loadingRooms"

        // Join Room
        case joinTitle = "join.title"
        case joinSubtitle = "join.subtitle"
        case joinEnterCode = "join.enterCode"
        case joinEnter = "join.enter"
        case joinOrLink = "join.orLink"
        case joinPlaceholder = "join.placeholder"

        // Profile
        case profileTitle = "profile.title"
        case profileStatsRooms = "profile.statsRooms"
        case profileStatsHours = "profile.statsHours"
        case profileStatsFriends = "profile.statsFriends"
        case profileHistory = "profile.history"
        case profileHistoryEmpty = "profile.historyEmpty"
        case profileClear = "profile.clear"
        case profileAccount = "profile.account"
        case profileEditProfile = "profile.editProfile"
        case profileNotifications = "profile.notifications"
        case profilePrivacy = "profile.privacy"
        case profileFriends = "profile.friends"
        case profileDangerZone = "profile.dangerZone"
        case profileDeleteAccount = "profile.deleteAccount"
        case profileDeleteConfirm = "profile.deleteConfirm"
        case profileDeleteMessage = "profile.deleteMessage"
        case profileSignOut = "profile.signOut"
        case profileLanguage = "profile.language"
        case profileLanguageSubtitle = "profile.languageSubtitle"

        // Video services
        case serviceYouTube = "service.youtube"
        case serviceVK = "service.vk"
        case serviceRuTube = "service.rutube"
        case serviceCustomURL = "service.customURL"
        case serviceBrowser = "service.browser"
        case serviceCinemas = "service.cinemas"
        case serviceCinemasHint = "service.cinemasHint"
        case serviceKinopoisk = "service.kinopoisk"
        case serviceIvi = "service.ivi"
        case serviceOkko = "service.okko"
        case serviceWink = "service.wink"
        case serviceStart = "service.start"
        case servicePremier = "service.premier"
        case serviceSmotrim = "service.smotrim"
        case serviceKion = "service.kion"

        // Friends
        case friendsTitle = "friends.title"
        case friendsTab = "friends.tabFriends"
        case friendsRequests = "friends.tabRequests"
        case friendsSearch = "friends.tabSearch"
        case friendsEmpty = "friends.empty"
        case friendsAddHint = "friends.addHint"
        case friendsOnline = "friends.online"
        case friendsOffline = "friends.offline"
        case friendsNoFriends = "friends.noFriends"
        case friendsNoFriendsHint = "friends.noFriendsHint"
        case friendsIncoming = "friends.incoming"
        case friendsOutgoing = "friends.outgoing"
        case friendsNoRequests = "friends.noRequests"
        case friendsNoRequestsHint = "friends.noRequestsHint"
        case friendsSearchPlaceholder = "friends.searchPlaceholder"
        case friendsNoResults = "friends.noResults"
        case friendsNoResultsHint = "friends.noResultsHint"
        case friendsWantsToAdd = "friends.wantsToAdd"
        case friendsWaiting = "friends.waiting"
        case friendsSent = "friends.sent"

        // Room creation
        case createTitle = "create.title"
        case createSource = "create.source"
        case createRoomSettings = "create.roomSettings"
        case createInviteFriends = "create.inviteFriends"
        case createVideoLink = "create.videoLink"
        case createExtractStream = "create.extractStream"
        case createExtracting = "create.extracting"
        case createNameOptional = "create.nameOptional"
        case createReady = "create.ready"
        case createRoomName = "create.roomName"
        case createRoomNamePlaceholder = "create.roomNamePlaceholder"
        case createMaxParticipants = "create.maxParticipants"
        case createWhoCanJoin = "create.whoCanJoin"
        case createPrivateHint = "create.privateHint"
        case createInviteSelected = "create.inviteSelected"
        case createFriendsEmpty = "create.friendsEmpty"
        case createFriendsEmptyHint = "create.friendsEmptyHint"
        case createInviteHint = "create.inviteHint"
        case createBack = "create.back"
        case createNext = "create.next"
        case createLaunch = "create.launch"
        case createExtractError = "create.extractError"

        // Chat
        case chatTitle = "chat.title"
        case chatPlaceholder = "chat.placeholder"
        case chatReport = "chat.report"
        case chatBlock = "chat.block"
        case chatReportTitle = "chat.reportTitle"
        case chatBlockTitle = "chat.blockTitle"
        case chatReportMessage = "chat.reportMessage"
        case chatBlockMessage = "chat.blockMessage"

        // Room moderation
        case reportRoom = "moderation.reportRoom"
        case reportRoomSent = "moderation.reportSent"
        case blockHost = "moderation.blockHost"
        case blockHostTitle = "moderation.blockHostTitle"
        case blockHostMessage = "moderation.blockHostMessage"
        case blockHostDone = "moderation.blockHostDone"

        // Room view
        case roomConnecting = "room.connecting"
        case roomLinkCopied = "room.linkCopied"
        case roomVoiceOn = "room.voiceOn"
        case roomJoinVoice = "room.joinVoice"
        case roomChat = "room.chat"
        case roomMessagePlaceholder = "room.messagePlaceholder"
        case roomLoading = "room.loading"
        case roomPremiumActivated = "room.premiumActivated"
        case roomVoiceError = "room.voiceError"

        // Ad
        case adBreak = "ad.break"
        case adBreakSubtitle = "ad.breakSubtitle"

        // Notifications settings
        case notifTitle = "notif.title"
        case notifPush = "notif.push"
        case notifPushSubtitle = "notif.pushSubtitle"
        case notifSounds = "notif.sounds"
        case notifSoundsSubtitle = "notif.soundsSubtitle"
        case notifFriendsOnline = "notif.friendsOnline"
        case notifFriendsOnlineSubtitle = "notif.friendsOnlineSubtitle"
        case notifNewRooms = "notif.newRooms"
        case notifNewRoomsSubtitle = "notif.newRoomsSubtitle"

        // Privacy settings
        case privacyTitle = "privacy.title"
        case privacyProfileVisibility = "privacy.profileVisibility"
        case privacyProfileVisibilitySubtitle = "privacy.profileVisibilitySubtitle"
        case privacyOnlineStatus = "privacy.onlineStatus"
        case privacyOnlineStatusSubtitle = "privacy.onlineStatusSubtitle"
        case privacyReadReceipts = "privacy.readReceipts"
        case privacyReadReceiptsSubtitle = "privacy.readReceiptsSubtitle"
        case privacyClearCache = "privacy.clearCache"
        case privacyClearCacheSubtitle = "privacy.clearCacheSubtitle"
        case privacyInfo = "privacy.info"

        // Paywall
        case paywallTitle = "paywall.title"
        case paywallTagline = "paywall.tagline"
        case paywallRestore = "paywall.restore"
        case paywallSelectPlan = "paywall.selectPlan"
        case paywallSubscribe = "paywall.subscribe"
        case paywallFeatureAdShield = "paywall.featureAdShield"
        case paywallFeatureAdShieldSub = "paywall.featureAdShieldSub"
        case paywallFeature4K = "paywall.feature4K"
        case paywallFeature4KSub = "paywall.feature4KSub"
        case paywallFeatureThemes = "paywall.featureThemes"
        case paywallFeatureThemesSub = "paywall.featureThemesSub"
        case paywallFeatureNick = "paywall.featureNick"
        case paywallFeatureNickSub = "paywall.featureNickSub"
        case paywallFeatureAvatar = "paywall.featureAvatar"
        case paywallFeatureAvatarSub = "paywall.featureAvatarSub"
        case paywallMonth1 = "paywall.month1"
        case paywallMonth3 = "paywall.month3"
        case paywallMonth12 = "paywall.month12"

        // Friends extras
        case friendsAlreadyFriends = "friends.alreadyFriends"

        // Chat extras
        case chatBlockMessageWithName = "chat.blockMessageWithName"

        // YouTube search
        case searchTitle = "search.title"
        case searchPlaceholder = "search.placeholder"
        case searchButton = "search.button"
        case searchEmpty = "search.empty"
        case searchHint = "search.hint"
        case searchError = "search.error"
        case searchUseThis = "search.useThis"

        // Home extras
        case homeNoRoomsEmpty = "home.noRoomsEmpty"
        case homeNoResults = "home.noResults"
        case homeNoResultsHint = "home.noResultsHint"
    }

    /// Главная таблица переводов: [ключ: [язык: перевод]].
    static let table: [Key: [AppLanguage: String]] = [
        .appName: [
            .russian: "Плинк",
            .english: "Plink",
            .chinese: "普林克"
        ],
        .appTagline: [
            .russian: "Смотрим вместе",
            .english: "Watch together",
            .chinese: "一起观看"
        ],

        .cancel: [
            .russian: "Отмена",
            .english: "Cancel",
            .chinese: "取消"
        ],
        .done: [
            .russian: "Готово",
            .english: "Done",
            .chinese: "完成"
        ],
        .back: [
            .russian: "Назад",
            .english: "Back",
            .chinese: "返回"
        ],
        .save: [
            .russian: "Сохранить",
            .english: "Save",
            .chinese: "保存"
        ],
        .delete: [
            .russian: "Удалить",
            .english: "Delete",
            .chinese: "删除"
        ],
        .error: [
            .russian: "Ошибка",
            .english: "Error",
            .chinese: "错误"
        ],
        .loading: [
            .russian: "Загрузка...",
            .english: "Loading...",
            .chinese: "加载中..."
        ],
        .search: [
            .russian: "Поиск",
            .english: "Search",
            .chinese: "搜索"
        ],

        // Login
        .loginTitle: [
            .russian: "Плинк",
            .english: "Plink",
            .chinese: "普林克"
        ],
        .loginTagline: [
            .russian: "Смотрим вместе",
            .english: "Watch together",
            .chinese: "一起观看"
        ],
        .loginEmail: [
            .russian: "Email",
            .english: "Email",
            .chinese: "邮箱"
        ],
        .loginPassword: [
            .russian: "Пароль",
            .english: "Password",
            .chinese: "密码"
        ],
        .loginUsername: [
            .russian: "Имя пользователя",
            .english: "Username",
            .chinese: "用户名"
        ],
        .loginSignIn: [
            .russian: "Войти",
            .english: "Sign In",
            .chinese: "登录"
        ],
        .loginSigningIn: [
            .russian: "Вход...",
            .english: "Signing in...",
            .chinese: "登录中..."
        ],
        .loginSignUp: [
            .russian: "Регистрация",
            .english: "Sign Up",
            .chinese: "注册"
        ],
        .loginDontHaveAccount: [
            .russian: "Нет аккаунта? Зарегистрироваться",
            .english: "Don't have an account? Sign Up",
            .chinese: "没有账号？注册"
        ],
        .loginAlreadyHaveAccount: [
            .russian: "Уже есть аккаунт? Войти",
            .english: "Already have an account? Sign In",
            .chinese: "已有账号？登录"
        ],
        .loginContinueWith: [
            .russian: "Продолжить через",
            .english: "Continue with",
            .chinese: "继续使用"
        ],
        .loginConnecting: [
            .russian: "Подключение к",
            .english: "Connecting to",
            .chinese: "正在连接"
        ],
        .loginTerms: [
            .russian: "Продолжая, вы соглашаетесь с Условиями использования и Политикой конфиденциальности.",
            .english: "By continuing, you agree to our Terms of Service and Privacy Policy.",
            .chinese: "继续即表示您同意我们的服务条款和隐私政策。"
        ],
        .loginCreateAccount: [
            .russian: "Создать аккаунт",
            .english: "Create Account",
            .chinese: "创建账号"
        ],
        .loginJoinParty: [
            .russian: "Присоединяйся к просмотру",
            .english: "Join the watch party",
            .chinese: "加入观看派对"
        ],

        // Home
        .homeDiscover: [
            .russian: "Обзор",
            .english: "Discover",
            .chinese: "发现"
        ],
        .homeWatchingNow: [
            .russian: "Смотрят сейчас",
            .english: "Watching now",
            .chinese: "正在观看"
        ],
        .homeCreateRoom: [
            .russian: "Создать комнату",
            .english: "Create a room",
            .chinese: "创建房间"
        ],
        .homeCreateRoomSubtitle: [
            .russian: "YouTube · кинотеатры · прямая ссылка",
            .english: "YouTube · cinemas · direct link",
            .chinese: "YouTube · 影院 · 直链"
        ],
        .homeSearchRooms: [
            .russian: "Поиск комнат...",
            .english: "Search rooms...",
            .chinese: "搜索房间..."
        ],
        .homePublicRooms: [
            .russian: "Общедоступные комнаты",
            .english: "Public rooms",
            .chinese: "公共房间"
        ],
        .homeTrending: [
            .russian: "Тренды",
            .english: "Trending",
            .chinese: "热门"
        ],
        .homeNoRooms: [
            .russian: "Нет активных комнат",
            .english: "No active rooms",
            .chinese: "没有活跃房间"
        ],
        .homeLoadingRooms: [
            .russian: "Загрузка комнат...",
            .english: "Loading rooms...",
            .chinese: "加载房间中..."
        ],

        // Join
        .joinTitle: [
            .russian: "Присоединиться",
            .english: "Join",
            .chinese: "加入"
        ],
        .joinSubtitle: [
            .russian: "Введите код комнаты или ссылку",
            .english: "Enter room code or link",
            .chinese: "输入房间代码或链接"
        ],
        .joinEnterCode: [
            .russian: "Код комнаты",
            .english: "Room code",
            .chinese: "房间代码"
        ],
        .joinEnter: [
            .russian: "Войти",
            .english: "Join",
            .chinese: "加入"
        ],
        .joinOrLink: [
            .russian: "или вставьте ссылку",
            .english: "or paste a link",
            .chinese: "或粘贴链接"
        ],
        .joinPlaceholder: [
            .russian: "ABC123 или https://...",
            .english: "ABC123 or https://...",
            .chinese: "ABC123 或 https://..."
        ],

        // Profile
        .profileTitle: [
            .russian: "Профиль",
            .english: "Profile",
            .chinese: "个人资料"
        ],
        .profileStatsRooms: [
            .russian: "Комнат",
            .english: "Rooms",
            .chinese: "房间"
        ],
        .profileStatsHours: [
            .russian: "Часов",
            .english: "Hours",
            .chinese: "小时"
        ],
        .profileStatsFriends: [
            .russian: "Друзей",
            .english: "Friends",
            .chinese: "好友"
        ],
        .profileHistory: [
            .russian: "История просмотров",
            .english: "Watch history",
            .chinese: "观看历史"
        ],
        .profileHistoryEmpty: [
            .russian: "Здесь появятся просмотренные видео",
            .english: "Watched videos will appear here",
            .chinese: "观看过的视频将显示在此处"
        ],
        .profileClear: [
            .russian: "Очистить",
            .english: "Clear",
            .chinese: "清除"
        ],
        .profileAccount: [
            .russian: "Аккаунт",
            .english: "Account",
            .chinese: "账户"
        ],
        .profileEditProfile: [
            .russian: "Редактировать профиль",
            .english: "Edit profile",
            .chinese: "编辑个人资料"
        ],
        .profileNotifications: [
            .russian: "Уведомления",
            .english: "Notifications",
            .chinese: "通知"
        ],
        .profilePrivacy: [
            .russian: "Конфиденциальность",
            .english: "Privacy",
            .chinese: "隐私"
        ],
        .profileFriends: [
            .russian: "Друзья",
            .english: "Friends",
            .chinese: "好友"
        ],
        .profileDangerZone: [
            .russian: "Опасная зона",
            .english: "Danger zone",
            .chinese: "危险区域"
        ],
        .profileDeleteAccount: [
            .russian: "Удалить аккаунт",
            .english: "Delete account",
            .chinese: "删除账户"
        ],
        .profileDeleteConfirm: [
            .russian: "Удалить аккаунт?",
            .english: "Delete account?",
            .chinese: "删除账户？"
        ],
        .profileDeleteMessage: [
            .russian: "Это действие необратимо. Все ваши данные будут удалены навсегда.",
            .english: "This action is irreversible. All your data will be permanently deleted.",
            .chinese: "此操作不可逆。您的所有数据将被永久删除。"
        ],
        .profileSignOut: [
            .russian: "Выйти",
            .english: "Sign Out",
            .chinese: "退出登录"
        ],
        .profileLanguage: [
            .russian: "Язык приложения",
            .english: "App language",
            .chinese: "应用语言"
        ],
        .profileLanguageSubtitle: [
            .russian: "Русский · English · 中文",
            .english: "Русский · English · 中文",
            .chinese: "Русский · English · 中文"
        ],

        // Video services
        .serviceYouTube: [
            .russian: "YouTube",
            .english: "YouTube",
            .chinese: "YouTube"
        ],
        .serviceVK: [
            .russian: "VK Видео",
            .english: "VK Video",
            .chinese: "VK 视频"
        ],
        .serviceRuTube: [
            .russian: "RuTube",
            .english: "RuTube",
            .chinese: "RuTube"
        ],
        .serviceCustomURL: [
            .russian: "Своя ссылка",
            .english: "Custom URL",
            .chinese: "自定义链接"
        ],
        .serviceBrowser: [
            .russian: "Браузер",
            .english: "Browser",
            .chinese: "浏览器"
        ],
        .serviceCinemas: [
            .russian: "Кинотеатры",
            .english: "Cinemas",
            .chinese: "影院"
        ],
        .serviceCinemasHint: [
            .russian: "Каждый зритель должен иметь свою подписку. Открывается в браузере с синхронизацией.",
            .english: "Each viewer needs their own subscription. Opens in browser with sync.",
            .chinese: "每位观众需有自己的订阅。在浏览器中打开并同步。"
        ],
        .serviceKinopoisk: [
            .russian: "Кинопоиск",
            .english: "Kinopoisk",
            .chinese: "Kinopoisk"
        ],
        .serviceIvi: [
            .russian: "Иви",
            .english: "Ivi",
            .chinese: "Ivi"
        ],
        .serviceOkko: [
            .russian: "Окко",
            .english: "Okko",
            .chinese: "Okko"
        ],
        .serviceWink: [
            .russian: "Wink",
            .english: "Wink",
            .chinese: "Wink"
        ],
        .serviceStart: [
            .russian: "Start",
            .english: "Start",
            .chinese: "Start"
        ],
        .servicePremier: [
            .russian: "Premier",
            .english: "Premier",
            .chinese: "Premier"
        ],
        .serviceSmotrim: [
            .russian: "Смотрим",
            .english: "Smotrim",
            .chinese: "Smotrim"
        ],
        .serviceKion: [
            .russian: "КИОН",
            .english: "KION",
            .chinese: "KION"
        ],

        // Friends
        .friendsTitle: [
            .russian: "Друзья",
            .english: "Friends",
            .chinese: "好友"
        ],
        .friendsTab: [
            .russian: "Друзья",
            .english: "Friends",
            .chinese: "好友"
        ],
        .friendsRequests: [
            .russian: "Заявки",
            .english: "Requests",
            .chinese: "请求"
        ],
        .friendsSearch: [
            .russian: "Поиск",
            .english: "Search",
            .chinese: "搜索"
        ],
        .friendsEmpty: [
            .russian: "Друзей пока нет",
            .english: "No friends yet",
            .chinese: "还没有好友"
        ],
        .friendsAddHint: [
            .russian: "Добавить в друзья",
            .english: "Add friend",
            .chinese: "添加好友"
        ],
        .friendsOnline: [
            .russian: "В сети",
            .english: "Online",
            .chinese: "在线"
        ],
        .friendsOffline: [
            .russian: "Не в сети",
            .english: "Offline",
            .chinese: "离线"
        ],
        .friendsNoFriends: [
            .russian: "Друзей пока нет",
            .english: "No friends yet",
            .chinese: "还没有好友"
        ],
        .friendsNoFriendsHint: [
            .russian: "Найдите друзей во вкладке «Поиск»",
            .english: "Find friends in the Search tab",
            .chinese: "在搜索标签页中查找好友"
        ],
        .friendsIncoming: [
            .russian: "Входящие заявки",
            .english: "Incoming requests",
            .chinese: "收到的请求"
        ],
        .friendsOutgoing: [
            .russian: "Исходящие заявки",
            .english: "Outgoing requests",
            .chinese: "发送的请求"
        ],
        .friendsNoRequests: [
            .russian: "Нет активных заявок",
            .english: "No active requests",
            .chinese: "没有活跃请求"
        ],
        .friendsNoRequestsHint: [
            .russian: "Поделитесь ссылкой-приглашением с друзьями",
            .english: "Share an invite link with friends",
            .chinese: "与好友分享邀请链接"
        ],
        .friendsSearchPlaceholder: [
            .russian: "Поиск по имени, нику или ID...",
            .english: "Search by name, nickname or ID...",
            .chinese: "按名字、昵称或ID搜索..."
        ],
        .friendsNoResults: [
            .russian: "Ничего не найдено",
            .english: "Nothing found",
            .chinese: "未找到结果"
        ],
        .friendsNoResultsHint: [
            .russian: "Попробуйте другое имя",
            .english: "Try a different name",
            .chinese: "尝试其他名字"
        ],
        .friendsWantsToAdd: [
            .russian: "хочет добавить вас в друзья",
            .english: "wants to add you as a friend",
            .chinese: "想加你为好友"
        ],
        .friendsWaiting: [
            .russian: "ожидает подтверждения",
            .english: "awaiting confirmation",
            .chinese: "等待确认"
        ],
        .friendsSent: [
            .russian: "Отправлено",
            .english: "Sent",
            .chinese: "已发送"
        ],

        // Room creation
        .createTitle: [
            .russian: "Новая комната",
            .english: "New Room",
            .chinese: "新房间"
        ],
        .createSource: [
            .russian: "Источник видео",
            .english: "Video source",
            .chinese: "视频来源"
        ],
        .createRoomSettings: [
            .russian: "Настройки комнаты",
            .english: "Room settings",
            .chinese: "房间设置"
        ],
        .createInviteFriends: [
            .russian: "Пригласить друзей",
            .english: "Invite friends",
            .chinese: "邀请好友"
        ],
        .createVideoLink: [
            .russian: "Ссылка на видео",
            .english: "Video link",
            .chinese: "视频链接"
        ],
        .createExtractStream: [
            .russian: "Получить прямой поток",
            .english: "Get direct stream",
            .chinese: "获取直链"
        ],
        .createExtracting: [
            .russian: "Извлечение…",
            .english: "Extracting…",
            .chinese: "提取中…"
        ],
        .createNameOptional: [
            .russian: "Название (необязательно)",
            .english: "Title (optional)",
            .chinese: "标题（可选）"
        ],
        .createReady: [
            .russian: "Готово к запуску ✓",
            .english: "Ready to launch ✓",
            .chinese: "准备启动 ✓"
        ],
        .createRoomName: [
            .russian: "Название комнаты",
            .english: "Room name",
            .chinese: "房间名称"
        ],
        .createRoomNamePlaceholder: [
            .russian: "напр., Кино-ночь 🍿",
            .english: "e.g. Movie Night 🍿",
            .chinese: "例如，电影之夜 🍿"
        ],
        .createMaxParticipants: [
            .russian: "Максимум участников",
            .english: "Max participants",
            .chinese: "最多参与者"
        ],
        .createWhoCanJoin: [
            .russian: "Кто может присоединиться?",
            .english: "Who can join?",
            .chinese: "谁可以加入？"
        ],
        .createPrivateHint: [
            .russian: "Приватная комната. Друзья смогут присоединиться только по прямой ссылке после запуска.",
            .english: "Private room. Friends can join only via direct link after launch.",
            .chinese: "私密房间。好友只能在启动后通过直接链接加入。"
        ],
        .createInviteSelected: [
            .russian: "Пригласить друзей",
            .english: "Invite friends",
            .chinese: "邀请好友"
        ],
        .createFriendsEmpty: [
            .russian: "Список друзей пуст",
            .english: "Your friends list is empty",
            .chinese: "好友列表为空"
        ],
        .createFriendsEmptyHint: [
            .russian: "Добавьте друзей в профиле",
            .english: "Add friends in profile",
            .chinese: "在个人资料中添加好友"
        ],
        .createInviteHint: [
            .russian: "Выбранным друзьям будет отправлено уведомление",
            .english: "Selected friends will be notified",
            .chinese: "将通知选中的好友"
        ],
        .createBack: [
            .russian: "Назад",
            .english: "Back",
            .chinese: "返回"
        ],
        .createNext: [
            .russian: "Далее",
            .english: "Next",
            .chinese: "下一步"
        ],
        .createLaunch: [
            .russian: "🚀 Запустить вечеринку",
            .english: "🚀 Launch party",
            .chinese: "🚀 启动派对"
        ],
        .createExtractError: [
            .russian: "Не удалось извлечь видео. Возможно, оно приватное или недоступно в вашем регионе.",
            .english: "Failed to extract video. It may be private or unavailable in your region.",
            .chinese: "无法提取视频。可能是私密的或在您所在的地区不可用。"
        ],

        // Chat
        .chatTitle: [
            .russian: "Чат",
            .english: "Chat",
            .chinese: "聊天"
        ],
        .chatPlaceholder: [
            .russian: "Написать сообщение...",
            .english: "Type a message...",
            .chinese: "输入消息..."
        ],
        .chatReport: [
            .russian: "Пожаловаться",
            .english: "Report",
            .chinese: "举报"
        ],
        .chatBlock: [
            .russian: "Заблокировать",
            .english: "Block",
            .chinese: "拉黑"
        ],
        .chatReportTitle: [
            .russian: "Пожаловаться на сообщение?",
            .english: "Report message?",
            .chinese: "举报消息？"
        ],
        .chatBlockTitle: [
            .russian: "Заблокировать пользователя?",
            .english: "Block user?",
            .chinese: "拉黑用户？"
        ],
        .chatReportMessage: [
            .russian: "Выберите причину жалобы. Модерация рассмотрит обращение.",
            .english: "Select a reason. Moderators will review your report.",
            .chinese: "选择原因。管理员将审核您的举报。"
        ],
        .chatBlockMessage: [
            .russian: "Вы больше не будете видеть сообщения от этого пользователя.",
            .english: "You will no longer see messages from this user.",
            .chinese: "您将不再看到此用户的消息。"
        ],

        // Room moderation
        .reportRoom: [
            .russian: "Пожаловаться на комнату?",
            .english: "Report room?",
            .chinese: "举报房间？"
        ],
        .reportRoomSent: [
            .russian: "Жалоба отправлена",
            .english: "Report sent",
            .chinese: "举报已发送"
        ],
        .blockHost: [
            .russian: "Заблокировать хоста?",
            .english: "Block host?",
            .chinese: "拉黑房主？"
        ],
        .blockHostTitle: [
            .russian: "Заблокировать",
            .english: "Block",
            .chinese: "拉黑"
        ],
        .blockHostMessage: [
            .russian: "Комнаты от этого хоста больше не будут отображаться.",
            .english: "Rooms from this host will no longer be shown.",
            .chinese: "此房主的房间将不再显示。"
        ],
        .blockHostDone: [
            .russian: "Хост заблокирован",
            .english: "Host blocked",
            .chinese: "房主已拉黑"
        ],

        // Room view
        .roomConnecting: [
            .russian: "Подключение к комнате...",
            .english: "Connecting to room...",
            .chinese: "正在连接房间..."
        ],
        .roomLinkCopied: [
            .russian: "Ссылка скопирована!",
            .english: "Link copied!",
            .chinese: "链接已复制！"
        ],
        .roomVoiceOn: [
            .russian: "Голос вкл",
            .english: "Voice On",
            .chinese: "语音开"
        ],
        .roomJoinVoice: [
            .russian: "Голос",
            .english: "Voice",
            .chinese: "语音"
        ],
        .roomChat: [
            .russian: "Чат",
            .english: "Chat",
            .chinese: "聊天"
        ],
        .roomMessagePlaceholder: [
            .russian: "Сообщение...",
            .english: "Message...",
            .chinese: "消息..."
        ],
        .roomLoading: [
            .russian: "Загрузка...",
            .english: "Loading...",
            .chinese: "加载中..."
        ],
        .roomPremiumActivated: [
            .russian: "Premium активирован! 🎉",
            .english: "Premium activated! 🎉",
            .chinese: "Premium 已激活！ 🎉"
        ],
        .roomVoiceError: [
            .russian: "Ошибка голоса: %@",
            .english: "Voice error: %@",
            .chinese: "语音错误：%@"
        ],

        // Ad
        .adBreak: [
            .russian: "Рекламная пауза",
            .english: "Ad break",
            .chinese: "广告暂停"
        ],
        .adBreakSubtitle: [
            .russian: "Скоро продолжим просмотр",
            .english: "Resuming shortly",
            .chinese: "即将继续观看"
        ],

        // Notifications settings
        .notifTitle: [
            .russian: "Уведомления",
            .english: "Notifications",
            .chinese: "通知"
        ],
        .notifPush: [
            .russian: "Push-уведомления",
            .english: "Push notifications",
            .chinese: "推送通知"
        ],
        .notifPushSubtitle: [
            .russian: "Получать уведомления о событиях",
            .english: "Receive event notifications",
            .chinese: "接收事件通知"
        ],
        .notifSounds: [
            .russian: "Звуки уведомлений",
            .english: "Notification sounds",
            .chinese: "通知声音"
        ],
        .notifSoundsSubtitle: [
            .russian: "Воспроизводить звук при уведомлении",
            .english: "Play sound on notification",
            .chinese: "收到通知时播放声音"
        ],
        .notifFriendsOnline: [
            .russian: "Друзья онлайн",
            .english: "Friends online",
            .chinese: "好友在线"
        ],
        .notifFriendsOnlineSubtitle: [
            .russian: "Уведомлять когда друзья заходят в сеть",
            .english: "Notify when friends come online",
            .chinese: "好友上线时通知"
        ],
        .notifNewRooms: [
            .russian: "Новые комнаты",
            .english: "New rooms",
            .chinese: "新房间"
        ],
        .notifNewRoomsSubtitle: [
            .russian: "Уведомлять о новых публичных комнатах",
            .english: "Notify about new public rooms",
            .chinese: "通知新公共房间"
        ],

        // Privacy settings
        .privacyTitle: [
            .russian: "Конфиденциальность",
            .english: "Privacy",
            .chinese: "隐私"
        ],
        .privacyProfileVisibility: [
            .russian: "Видимость профиля",
            .english: "Profile visibility",
            .chinese: "个人资料可见性"
        ],
        .privacyProfileVisibilitySubtitle: [
            .russian: "Другие пользователи могут видеть ваш профиль",
            .english: "Others can see your profile",
            .chinese: "其他人可以查看您的个人资料"
        ],
        .privacyOnlineStatus: [
            .russian: "Онлайн-статус",
            .english: "Online status",
            .chinese: "在线状态"
        ],
        .privacyOnlineStatusSubtitle: [
            .russian: "Показывать когда вы в сети",
            .english: "Show when you're online",
            .chinese: "显示您在线的时间"
        ],
        .privacyReadReceipts: [
            .russian: "Отчёты о прочтении",
            .english: "Read receipts",
            .chinese: "已读回执"
        ],
        .privacyReadReceiptsSubtitle: [
            .russian: "Показывать прочитанные сообщения",
            .english: "Show read messages",
            .chinese: "显示已读消息"
        ],
        .privacyClearCache: [
            .russian: "Очистить кэш",
            .english: "Clear cache",
            .chinese: "清除缓存"
        ],
        .privacyClearCacheSubtitle: [
            .russian: "Удалить временные данные",
            .english: "Remove temporary data",
            .chinese: "删除临时数据"
        ],
        .privacyInfo: [
            .russian: "Данные хранятся локально на вашем устройстве. Мы не передаём вашу личную информацию третьим лицам.",
            .english: "Data is stored locally on your device. We don't share your personal information with third parties.",
            .chinese: "数据存储在您的设备本地。我们不会与第三方共享您的个人信息。"
        ],

        // Paywall
        .paywallTitle: [
            .russian: "SyncWatch Premium",
            .english: "SyncWatch Premium",
            .chinese: "SyncWatch Premium"
        ],
        .paywallTagline: [
            .russian: "Без рекламы. Без ограничений. Полный контроль.",
            .english: "No ads. No limits. Full control.",
            .chinese: "无广告。无限制。完全掌控。"
        ],
        .paywallRestore: [
            .russian: "Восстановить покупки",
            .english: "Restore purchases",
            .chinese: "恢复购买"
        ],
        .paywallSelectPlan: [
            .russian: "Выберите план",
            .english: "Choose a plan",
            .chinese: "选择方案"
        ],
        .paywallSubscribe: [
            .russian: "Подписаться",
            .english: "Subscribe",
            .chinese: "订阅"
        ],
        .paywallFeatureAdShield: [
            .russian: "Рекламный щит для друзей",
            .english: "Ad shield for friends",
            .chinese: "好友广告屏蔽"
        ],
        .paywallFeatureAdShieldSub: [
            .russian: "Создайте комнату — никто из гостей не увидит рекламу",
            .english: "Create a room — none of the guests will see ads",
            .chinese: "创建房间——所有嘉宾都不会看到广告"
        ],
        .paywallFeature4K: [
            .russian: "Разрешение 2K / 4K",
            .english: "2K / 4K resolution",
            .chinese: "2K / 4K 分辨率"
        ],
        .paywallFeature4KSub: [
            .russian: "Максимальное качество видео для ваших комнат",
            .english: "Maximum video quality for your rooms",
            .chinese: "房间的最高画质"
        ],
        .paywallFeatureThemes: [
            .russian: "Темы оформления комнат",
            .english: "Room themes",
            .chinese: "房间主题"
        ],
        .paywallFeatureThemesSub: [
            .russian: "Кастомные градиенты чата и неоновые рамки плеера",
            .english: "Custom chat gradients and neon player frames",
            .chinese: "自定义聊天渐变和霓虹播放器边框"
        ],
        .paywallFeatureNick: [
            .russian: "Оформление ника",
            .english: "Nickname styling",
            .chinese: "昵称样式"
        ],
        .paywallFeatureNickSub: [
            .russian: "Градиентные цвета ника в чате и бегущей строке",
            .english: "Gradient nickname colors in chat and ticker",
            .chinese: "聊天和滚动条中的渐变昵称"
        ],
        .paywallFeatureAvatar: [
            .russian: "Рамки аватара",
            .english: "Avatar frames",
            .chinese: "头像边框"
        ],
        .paywallFeatureAvatarSub: [
            .russian: "Неоновые, золотые и анимированные обводки",
            .english: "Neon, gold and animated borders",
            .chinese: "霓虹、金色和动态边框"
        ],
        .paywallMonth1: [
            .russian: "1 месяц",
            .english: "1 month",
            .chinese: "1 个月"
        ],
        .paywallMonth3: [
            .russian: "3 месяца",
            .english: "3 months",
            .chinese: "3 个月"
        ],
        .paywallMonth12: [
            .russian: "12 месяцев",
            .english: "12 months",
            .chinese: "12 个月"
        ],

        // Friends extras
        .friendsAlreadyFriends: [
            .russian: "✓ Друзья",
            .english: "✓ Friends",
            .chinese: "✓ 好友"
        ],

        // Chat extras
        .chatBlockMessageWithName: [
            .russian: "Вы больше не будете видеть сообщения от «%@».",
            .english: "You will no longer see messages from \"%@\".",
            .chinese: "您将不再看到\"%@\"的消息。"
        ],

        // YouTube search
        .searchTitle: [
            .russian: "Поиск YouTube",
            .english: "YouTube search",
            .chinese: "YouTube 搜索"
        ],
        .searchPlaceholder: [
            .russian: "Введите название ролика...",
            .english: "Type a video title...",
            .chinese: "输入视频标题..."
        ],
        .searchButton: [
            .russian: "Искать",
            .english: "Search",
            .chinese: "搜索"
        ],
        .searchEmpty: [
            .russian: "Введите запрос и нажмите «Искать»",
            .english: "Type a query and press Search",
            .chinese: "输入关键词并点击搜索"
        ],
        .searchHint: [
            .russian: "Найдём ролик вместе",
            .english: "Let's find a video together",
            .chinese: "一起找视频吧"
        ],
        .searchError: [
            .russian: "Поиск не удался. Попробуйте ещё раз.",
            .english: "Search failed. Try again.",
            .chinese: "搜索失败。请重试。"
        ],
        .searchUseThis: [
            .russian: "Выбрать этот ролик",
            .english: "Use this video",
            .chinese: "使用此视频"
        ],

        // Home extras
        .homeNoRoomsEmpty: [
            .russian: "Создай комнату и пригласи друзей!",
            .english: "Create a room and invite friends!",
            .chinese: "创建房间并邀请好友！"
        ],
        .homeNoResults: [
            .russian: "Комнаты не найдены",
            .english: "No rooms found",
            .chinese: "未找到房间"
        ],
        .homeNoResultsHint: [
            .russian: "Попробуй другой запрос",
            .english: "Try another search",
            .chinese: "尝试其他搜索"
        ]
    ]
}

// MARK: - View Helper
extension View {
    /// Доступ к локализации из любого View.
    var L: LocalizationManager { LocalizationManager.shared }
}
