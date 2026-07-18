
// Plink/Views/Home/RoomCreationView.swift
// PLINK_M11: Beautiful room creation with service carousel

import SwiftUI

// MARK: - Step
enum RoomCreationStep { case service, content, setup, creating }

// MARK: - ServiceCardKind
enum ServiceCardKind { case direct, subscription, other }

// MARK: - Main View
struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: RoomCreationStep = .service
    @State private var selectedService: VideoService? = nil
    @State private var detectedVideo: DetectedVideo? = nil
    @State private var roomName: String = ""
    @State private var isPublic: Bool = true
    @State private var showAuthSheet: Bool = false
    @State private var pendingAuthService: VideoService? = nil
    @State private var isCreating: Bool = false
    @State private var heroOffset: CGFloat = 0

    let onCreate: ((String, VideoService, DetectedVideo?) -> Void)?

    init(onCreate: ((String, VideoService, DetectedVideo?) -> Void)? = nil) {
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Cinema2026.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        switch step {
                        case .service:  serviceStep
                        case .content:  contentStep
                        case .setup:    setupStep
                        case .creating: creatingStep
                        }
                    }
                }

                // Floating back button
                if step != .service {
                    VStack {
                        Spacer()
                        HStack {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    switch step {
                                    case .content: step = .service
                                    case .setup:   step = .content
                                    default: break
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text("Назад")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Cinema2026.secondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(stepTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                }
            }
        }
        .sheet(isPresented: $showAuthSheet) {
            if let svc = pendingAuthService {
                ServiceAuthSheet(service: svc) {
                    ServiceAuthStore.markAuthorized(svc.serviceType)
                    showAuthSheet = false
                    selectedService = svc
                    withAnimation { step = .content }
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .service:  return "Создать комнату"
        case .content:  return selectedService?.title ?? "Выбор видео"
        case .setup:    return "Настройка"
        case .creating: return "Создаём..."
        }
    }

    // MARK: - Service groups
    private var syncableServices: [VideoService] {
        [.youtube, .vk, .rutube]
    }
    private var cinemaServices: [VideoService] {
        [.kinopoisk, .netflix, .okko, .ivi, .disney, .wink, .start, .premier, .kion]
    }
    private var otherServices: [VideoService] {
        [.browser, .customURL]
    }

    // MARK: - Step 1: Service
    private var serviceStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero greeting
            VStack(alignment: .leading, spacing: 8) {
                Text("Что смотрим?")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(Cinema2026.text)
                Text("Выбери сервис — пригласи друзей и смотрите вместе")
                    .font(.system(size: 15))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 22)

            // Section: Direct sync
            sectionLabel("СИНХРОННЫЕ СЕРВИСЫ", subtitle: "Бесплатно — прямой синх без подписки")
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // Large horizontal hero cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(syncableServices, id: \.self) { svc in
                        DirectServiceCard(service: svc) { selectService(svc) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .padding(.bottom, 30)

            // Section: Cinemas
            sectionLabel("КИНОТЕАТРЫ · УНИКАЛЬНОЕ", subtitle: "Host входит в аккаунт. Гости смотрят через Plink", accent: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            LazyVGrid(
                columns: [.init(.flexible(), spacing: 12), .init(.flexible(), spacing: 12), .init(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(cinemaServices, id: \.self) { svc in
                    CinemaServiceCard(service: svc) { selectService(svc) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)

            // Section: Other
            sectionLabel("ДРУГОЕ", subtitle: "Любая ссылка или встроенный браузер")
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            VStack(spacing: 10) {
                ForEach(otherServices, id: \.self) { svc in
                    OtherServiceRow(service: svc) { selectService(svc) }
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 60)
        }
    }

    private func selectService(_ svc: VideoService) {
        if svc.serviceType.requiresAuth && !ServiceAuthStore.hasAccess(to: svc.serviceType) {
            pendingAuthService = svc
            showAuthSheet = true
        } else {
            selectedService = svc
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = .content }
        }
    }

    private func sectionLabel(_ title: String, subtitle: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if accent {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Cinema2026.accent)
                }
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(accent ? Cinema2026.accent : Cinema2026.secondary)
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Cinema2026.secondary.opacity(0.8))
        }
    }

    // MARK: - Step 2: Content
    private var contentStep: some View {
        Group {
            if let svc = selectedService {
                ServiceBrowserView(service: svc) { video in
                    detectedVideo = video
                    roomName = video.title
                    withAnimation { step = .setup }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    // MARK: - Step 3: Setup
    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let video = detectedVideo {
                // Video preview
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { img in
                        img.resizable().aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Cinema2026.surface)
                    }
                    .frame(height: 200)
                    .clipped()

                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

                    if let svc = selectedService {
                        ServiceLogoView(service: svc, size: 28)
                            .padding(14)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                // Room name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Название комнаты")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                    TextField("Как назвём комнату?", text: $roomName)
                        .font(.system(size: 17))
                        .foregroundStyle(Cinema2026.text)
                        .padding(14)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                }

                // Privacy toggle
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isPublic ? "Открытая комната" : "Закрытая комната")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Cinema2026.text)
                        Text(isPublic ? "Любой может присоединиться" : "Только по ссылке")
                            .font(.system(size: 12))
                            .foregroundStyle(Cinema2026.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $isPublic)
                        .labelsHidden()
                        .tint(Cinema2026.accent)
                }
                .padding(16)
                .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))

                // Create button
                Button {
                    withAnimation { step = .creating }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        onCreate?(roomName, selectedService ?? .youtube, detectedVideo)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                        Text("Создать комнату")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [Cinema2026.accent, Cinema2026.accent.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .foregroundStyle(.black)
                    .shadow(color: Cinema2026.accent.opacity(0.4), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 4: Creating
    private var creatingStep: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(Cinema2026.accent)
            Text("Создаём комнату...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Spacer()
        }
        .frame(minHeight: 400)
    }
}

// MARK: - Direct Service Card (YouTube / VK / Rutube)
struct DirectServiceCard: View {
    let service: VideoService
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Brand gradient
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [service.accentColor.opacity(0.9), service.accentColor.opacity(0.4), .black.opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 210, height: 140)

                // Inner glow
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(service.accentColor.opacity(0.35), lineWidth: 1)
                    .frame(width: 210, height: 140)

                // SYNC badge
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                            Text("SYNC")
                                .font(.system(size: 8, weight: .black))
                                .tracking(1.2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(12)
                    }
                    Spacer()
                }
                .frame(width: 210, height: 140)

                // Bottom info
                HStack(alignment: .bottom, spacing: 10) {
                    ServiceLogoView(service: service, size: 42)
                        .shadow(color: .black.opacity(0.4), radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(service.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(14)
            }
            .frame(width: 210, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: service.accentColor.opacity(0.35), radius: 14, x: 0, y: 6)
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false })
    }
}

// MARK: - Cinema Service Card (Kinopoisk, Netflix, Okko...)
struct CinemaServiceCard: View {
    let service: VideoService
    let action: () -> Void
    @State private var pressed = false

    private var isAuthorized: Bool {
        ServiceAuthStore.hasAccess(to: service.serviceType)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(service.accentColor.opacity(0.12))
                            .frame(width: 64, height: 64)
                        ServiceLogoView(service: service, size: 44)
                    }

                    Text(service.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    // Host badge
                    HStack(spacing: 3) {
                        Image(systemName: isAuthorized ? "checkmark.circle.fill" : "crown.fill")
                            .font(.system(size: 8))
                        Text(isAuthorized ? "Вход" : "Host")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(isAuthorized ? .green : Cinema2026.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isAuthorized ? Color.green : Cinema2026.accent).opacity(0.12),
                        in: Capsule()
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 6)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Cinema2026.surface)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isAuthorized
                                ? LinearGradient(colors: [.green.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [service.accentColor.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }

                // Green dot if authorized
                if isAuthorized {
                    Circle().fill(Color.green).frame(width: 8, height: 8).padding(8)
                }
            }
            .scaleEffect(pressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false })
    }
}

// MARK: - Other Service Row (Browser, Custom URL)
struct OtherServiceRow: View {
    let service: VideoService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(service.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    ServiceLogoView(service: service, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                    Text(service.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Service Auth Sheet
struct ServiceAuthSheet: View {
    let service: VideoService
    let onAuthorized: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var webShown: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                // Logo & brand
                ZStack {
                    Circle()
                        .fill(service.accentColor.opacity(0.15))
                        .frame(width: 110, height: 110)
                    ServiceLogoView(service: service, size: 72)
                }

                VStack(spacing: 10) {
                    Text("Войдите в \(service.title)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                    Text("Чтобы стать Host, необходима подписка \(service.title).
Гости смотрят бесплатно через Plink.")
                        .font(.system(size: 15))
                        .foregroundStyle(Cinema2026.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                // Benefits
                VStack(spacing: 12) {
                    authBenefit(icon: "key.fill", text: "Войдите один раз — сессия сохраняется")
                    authBenefit(icon: "iphone", text: "Чтобы снова войти — откройте Настройки → Сервисы")
                    authBenefit(icon: "person.2.fill", text: "Гостям подписка не нужна")
                }
                .padding(.horizontal, 30)

                Spacer()

                // CTA
                Button {
                    webShown = true
                } label: {
                    HStack(spacing: 10) {
                        ServiceLogoView(service: service, size: 22)
                        Text("Войти через \(service.title)")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [service.accentColor, service.accentColor.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: service.accentColor.opacity(0.4), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                Button("Позже") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Cinema2026.secondary)
                    .padding(.bottom, 30)
            }
            .background(Cinema2026.bg.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $webShown) {
                ServiceBrowserView(service: service) { _ in
                    onAuthorized()
                }
            }
        }
    }

    private func authBenefit(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.accent)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.text)
            Spacer()
        }
    }
}
