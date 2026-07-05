import SwiftUI

// MARK: - Плинк — Bioluminescent Dark Premium
//
// ЕДИНАЯ строгая палитра. Никаких случайных цветов.
// • Фон — обсидиан #0A0D14 (сквозной по всем экранам).
// • Свечение (биолюминесценция) — строго cyan/teal + мягкий изумруд.
// • Стекло — полупрозрачный белый 3-5%, без цветных подложек.
// • Все старые токены (raveAccent, raveWarning, ravePurple) замаплены
//   на единый спектр, чтобы весь UI автоматически встал в одну палитру.
extension Color {
    // ════════════════════════════════════════════════════════════════
    // MARK: - База
    // ════════════════════════════════════════════════════════════════

    /// Обсидиан — основной сквозной фон (#0A0D14)
    static let raveBackground = Color(hex: 0x0A0D14)
    /// Фон карточек (поверх стекла) — чуть светлее обсидиана
    static let raveCard = Color(hex: 0x11151F)
    /// Границы / surfaces
    static let raveSurface = Color(hex: 0x1A1F2E)

    // ════════════════════════════════════════════════════════════════
    // MARK: - Биолюминесценция (ЕДИНЫЙ спектр свечения)
    // ════════════════════════════════════════════════════════════════

    /// Cyan — основной свет / акцент (CTA, активные элементы, рамки)
    static let bioCyan = Color(hex: 0x2DE2E6)
    /// Teal — вторичный (глубина свечения)
    static let bioTeal = Color(hex: 0x0EB5C9)
    /// Изумрудный — мягкий glow (live-статус, успех)
    static let bioEmerald = Color(hex: 0x26D9A4)

    // ════════════════════════════════════════════════════════════════
    // MARK: - Тёплые акценты (для разнообразия и warmth)
    // Используются точечно: реакции, друзья, premium-бейджи.
    // Основной UI остаётся в cyan/teal/emerald спектре.
    // ════════════════════════════════════════════════════════════════

    /// Коралл — для reactions и social warmth (#FF6B6B)
    static let bioCoral = Color(hex: 0xFF6B6B)
    /// Янтарь — для premium-бейджей и achievements (#FFB454)
    static let bioAmber = Color(hex: 0xFFB454)
    /// Розовый кварц — для profile и romance (#FF8FAB)
    static let bioRose = Color(hex: 0xFF8FAB)

    // ── Псевдонимы (алиасы для читаемости) ───────────────────────────
    static let ravePrimary = bioCyan
    static let raveCyan = bioCyan
    static let raveGreen = bioEmerald
    static let raveCoral = bioCoral
    static let raveAmber = bioAmber
    static let raveRose = bioRose

    // ════════════════════════════════════════════════════════════════
    // MARK: - Семантические цвета (ЗАМУНЛЕНЫ на единый спектр)
    // ════════════════════════════════════════════════════════════════
    // ВАЖНО: все прежние розовые/оранжевые/фиолетовые/золотые токены
    // теперь указывают на cyan/teal/emerald, чтобы старый UI стал единым.

    static let raveAccent = bioCyan
    static let raveSecondary = bioTeal
    static let raveWarning = bioEmerald
    static let ravePurple = bioTeal
    /// Красный — единственный не-cyan (danger, без этого никак)
    static let raveDanger = Color(hex: 0xFF4D6D)

    // ════════════════════════════════════════════════════════════════
    // MARK: - Текст (контраст на обсидиане)
    // ════════════════════════════════════════════════════════════════

    static let raveTextPrimary = Color.white
    static let raveTextSecondary = Color(white: 0.68)
    static let raveTextTertiary = Color(white: 0.42)

    // ════════════════════════════════════════════════════════════════
    // MARK: - Стекло
    // ════════════════════════════════════════════════════════════════

    /// Полупрозрачный белый для glass-фона (3-5%)
    static let raveGlass = Color.white.opacity(0.04)

    // ════════════════════════════════════════════════════════════════
    // MARK: - Градиенты (всё в cyan/emerald спектре)
    // ════════════════════════════════════════════════════════════════

    /// Главный градиент: cyan → teal
    static let raveGradient = LinearGradient(
        colors: [Color(hex: 0x2DE2E6), Color(hex: 0x0EB5C9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Акцентный градиент: cyan → emerald
    static let raveTriGradient = LinearGradient(
        colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Glow градиент (свечение)
    static let raveGlowGradient = LinearGradient(
        colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Premium-градиент: teal → обсидиан (премиум без короны)
    static let premiumGradient = LinearGradient(
        colors: [Color(hex: 0x0EB5C9), Color(hex: 0x0A0D14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Premium-градиент для обводки (кольцо)
    static let premiumRingGradient = LinearGradient(
        colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4), Color(hex: 0x0EB5C9)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Фоновый градиент — обсидиан (для splash и базовых слоёв)
    static let raveBgGradient = LinearGradient(
        colors: [Color(hex: 0x0A0D14), Color(hex: 0x0C1018), Color(hex: 0x0A0D14)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Неоновая обводка для glassmorphism (cyan → emerald)
    static let bioNeonRing = LinearGradient(
        colors: [
            Color(hex: 0x2DE2E6).opacity(0.5),
            Color(hex: 0x26D9A4).opacity(0.25),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // ════════════════════════════════════════════════════════════════
    // MARK: - Тёплые градиенты (для reactions, friends, premium)
    // ════════════════════════════════════════════════════════════════

    /// Реакции: coral → amber (тёплая эмоция)
    static let raveReactionGradient = LinearGradient(
        colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFFB454)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Друзья: rose → coral (social warmth)
    static let raveFriendsGradient = LinearGradient(
        colors: [Color(hex: 0xFF8FAB), Color(hex: 0xFF6B6B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Premium: amber → cyan (дорогой, но в палитре)
    static let ravePremiumAccent = LinearGradient(
        colors: [Color(hex: 0xFFB454), Color(hex: 0x2DE2E6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Закат: coral → emerald (контраст тёплого и холодного)
    static let raveSunsetGradient = LinearGradient(
        colors: [Color(hex: 0xFF6B6B), Color(hex: 0x26D9A4)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Глубоководный: cyan → rose (биолюминесценция + теплый акцент)
    static let raveAbyssGradient = LinearGradient(
        colors: [Color(hex: 0x2DE2E6), Color(hex: 0xFF8FAB)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 🔧 Pack v3: Admin text gradient — переливающийся красный (для ников админов в чате)
    static let adminTextGradient = LinearGradient(
        colors: [
            Color(hex: 0xFF4D6D),
            Color(hex: 0xFF8FA3),
            Color(hex: 0xFF4D6D),
            Color(hex: 0xFF6B6B),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    // ── Устаревшие bio-токены (для обратной совместимости) ──────────
    static let bioObsidian = Color(hex: 0x0A0D14)
    static let bioMidnight = Color(hex: 0x0C1018)
    static let bioInk = Color(hex: 0x0A0D14)
    static let bioUltramarine = Color(hex: 0x0EB5C9)
}

// MARK: - Hex
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Glow Helpers
extension Color {
    var glowShadow: Color { self.opacity(0.45) }
}

extension View {
    /// Мягкое неоновое свечение (cyan по умолчанию).
    func neonGlow(color: Color = .bioCyan, radius: CGFloat = 14, y: CGFloat = 4) -> some View {
        self.shadow(color: color.glowShadow, radius: radius, x: 0, y: y)
    }

    func chatTextShadow() -> some View {
        self.shadow(color: .black.opacity(0.9), radius: 2.5, x: 0, y: 1)
    }
}
