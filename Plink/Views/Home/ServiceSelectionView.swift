import SwiftUI

// MARK: - Service Selection v4 — "3 Hyper-Buttons"
///
/// Три крупные гипер-кнопки-категории вместо длинного списка:
/// 1. Видеосервисы → полноэкранный экран с YouTube, VK, Rutube, Netflix, Disney+
/// 2. Кинотеатры → экран с Кинопоиск, Ivi, Wink, Okko, Start, Premier, СМОТРИМ, КИОН
/// 3. Браузер/Своя ссылка → экран с полем ввода URL
struct ServiceSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (VideoService) -> Void

    @State private var appeared = false
    @State private var selectedCategory: ServiceCategory?

    enum ServiceCategory: String, Identifiable {
        case video, cinema, browser
        var id: String { rawValue }
    }

    private let videoServices: [VideoService] = [.youtube, .vk, .rutube, .netflix, .disney]
    private let cinemaServices: [VideoService] = [.kinopoisk, .ivi, .wink, .okko, .start, .premier, .smotrim, .kion]

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                premiumNav

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Гипер-кнопка 1: Видеосервисы
                        hyperButton(
                            title: "Видеосервисы",
                            subtitle: "YouTube · VK · Rutube · Netflix · Disney+",
                            icon: "play.rectangle.fill",
                            gradient: [Color.ravePrimary.opacity(0.3), .black],
                            action: { selectedCategory = .video }
                        )

                        // Гипер-кнопка 2: Кинотеатры
                        hyperButton(
                            title: "Кинотеатры",
                            subtitle: "Кинопоиск · Ivi · Okko · Wink · и другие",
                            icon: "film.stack",
                            gradient: [Color.raveAccent.opacity(0.3), .black],
                            action: { selectedCategory = .cinema }
                        )

                        // Гипер-кнопка 3: Браузер / Своя ссылка
                        hyperButton(
                            title: "Браузер / Своя ссылка",
                            subtitle: "Открой любой сайт или вставь URL",
                            icon: "safari.fill",
                            gradient: [Color.raveCyan.opacity(0.3), .black],
                            action: { selectedCategory = .browser }
                        )

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
        .sheet(item: $selectedCategory) { category in
            switch category {
            case .video:
                ServiceGridScreen(
                    title: "Видеосервисы",
                    services: videoServices,
                    onSelect: { service in
                        selectedCategory = nil
                        onSelect(service)
                    }
                )
            case .cinema:
                ServiceGridScreen(
                    title: "Кинотеатры",
                    services: cinemaServices,
                    onSelect: { service in
                        selectedCategory = nil
                        onSelect(service)
                    }
                )
            case .browser:
                BrowserInputScreen { service in
                    selectedCategory = nil
                    onSelect(service)
                }
            }
        }
    }

    // MARK: - Premium Navigation

    private var premiumNav: some View {
        HStack {
            Button {
                HapticManager.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.raveTextPrimary)
                    .frame(width: 40, height: 40)
                    .glassCard(cornerRadius: 20, opacity: 0.06)
            }
            .buttonStyle(PremiumButtonStyle(glowColor: .clear))

            Spacer()

            Text("Выбор сервиса")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.raveTextPrimary)

            Spacer()

            Color.clear.frame(width: 40, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Hyper Button (крупная карточка-категория)

    private func hyperButton(title: String, subtitle: String, icon: String, gradient: [Color], action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.raveTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.raveTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.raveTextTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassCard(cornerRadius: 20, opacity: 0.04)
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }
}

// MARK: - Service Grid Screen (сетка 2×2 или 3×2 сервисов)
///
/// Полноэкранный экран категории с плитками-сервисами.
struct ServiceGridScreen: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let services: [VideoService]
    var onSelect: (VideoService) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(services) { service in
                            Button {
                                HapticManager.impact(.medium)
                                onSelect(service)
                            } label: {
                                VStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(service.accentColor.opacity(0.12))
                                            .frame(width: 64, height: 64)
                                        ServiceLogoIcon(service: service, size: 32)
                                    }

                                    Text(service.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.raveTextPrimary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .glassCard(cornerRadius: 18, opacity: 0.04)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ravePrimary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Browser Input Screen (поле ввода URL)
struct BrowserInputScreen: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (VideoService) -> Void
    @State private var url = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground(orbColors: [Color(hex: 0x22D3EE), Color.bioCyan, Color(hex: 0x1A2A6C)])

                VStack(spacing: 28) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.raveCyan.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "safari.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.raveCyan)
                    }

                    VStack(spacing: 8) {
                        Text("Браузер / Своя ссылка")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.raveTextPrimary)
                        Text("Вставьте ссылку на видео или сайт")
                            .font(.system(size: 15))
                            .foregroundColor(.raveTextSecondary)
                    }

                    TextField("https://...", text: $url)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                        .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        Button {
                            HapticManager.impact(.medium)
                            onSelect(.browser)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                Text("Открыть браузер")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.raveCyan.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.raveCyan.opacity(0.4), lineWidth: 0.5))
                        }

                        Button {
                            HapticManager.impact(.medium)
                            onSelect(.customURL)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                Text("По ссылке")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.raveGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
                .dismissKeyboardOnTap()
            }
            .navigationTitle("Браузер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ravePrimary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ServiceSelectionView(onSelect: { _ in })
}
