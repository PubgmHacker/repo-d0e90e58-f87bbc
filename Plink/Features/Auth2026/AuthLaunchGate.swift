// Plink/Features/Auth2026/AuthLaunchGate.swift — MVP: skip + notifications + deferred deep links
// Functionality only — no design changes to splash/auth UI chrome.

import SwiftUI
import UserNotifications
import UIKit

enum LaunchDestination: Equatable {
    case restoringSession
    case authentication
    case onboarding
    case app
}

struct AuthLaunchGate: View {
    @State private var destination: LaunchDestination = .restoringSession
    @State private var authRoute: AuthRoute = .login
    @State private var pendingURL: URL?
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter

    let dependencies: AppDependencies
    let onboardingStore: OnboardingStoring

    var body: some View {
        ZStack {
            switch destination {
            case .restoringSession:
                CinematicSplashView()
                    .transition(.opacity)

            case .authentication:
                authFlow
                    .transition(.opacity)

            case .onboarding:
                OnboardingFlow(
                    onFinish: completeOnboarding,
                    onSkip: skipOnboarding
                )
                .transition(.opacity)

            case .app:
                PlinkAppShell(dependencies: dependencies)
                    .transition(.opacity)
                    .onAppear { flushPendingDeepLink() }
            }
        }
        .task { await restoreSession() }
        .animation(.easeOut(duration: 0.32), value: destination)
        .onReceive(NotificationCenter.default.publisher(for: .plinkSignedOut)) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                destination = .authentication
            }
        }
        .onOpenURL { url in
            if destination == .app {
                deepLinkRouter.handle(url)
            } else {
                pendingURL = url
            }
        }
        .onChange(of: destination) { _, newValue in
            if newValue == .app { flushPendingDeepLink() }
        }
    }

    @ViewBuilder
    private var authFlow: some View {
        switch authRoute {
        case .login:
            LoginView2026(
                onAuthenticated: handleAuthenticated,
                onRegister: { authRoute = .registration }
            )
        case .registration:
            RegistrationView2026(
                onRegistered: handleAuthenticated,
                onLogin: { authRoute = .login }
            )
        }
    }

    private func restoreSession() async {
        async let minimumSplash: Void = Task.sleep(for: .milliseconds(650))
        let authService = dependencies.authService
        let token = authService.authToken
        _ = try? await minimumSplash

        if token != nil {
            let user = await authService.currentUser()
            if user != nil {
                destination = onboardingStore.needsCurrentOnboarding ? .onboarding : .app
            } else {
                let refreshed = await authService.getFreshToken()
                if refreshed != nil {
                    destination = onboardingStore.needsCurrentOnboarding ? .onboarding : .app
                } else {
                    destination = .authentication
                }
            }
        } else {
            destination = .authentication
        }
    }

    private func handleAuthenticated() {
        destination = onboardingStore.needsCurrentOnboarding ? .onboarding : .app
        if destination == .app { flushPendingDeepLink() }
    }

    private func completeOnboarding() {
        requestNotificationPermission()
        onboardingStore.markCompleted(version: OnboardingVersion.current)
        destination = .app
        flushPendingDeepLink()
    }

    private func skipOnboarding() {
        requestNotificationPermission()
        onboardingStore.markCompleted(version: OnboardingVersion.current)
        destination = .app
        flushPendingDeepLink()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    private func flushPendingDeepLink() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        deepLinkRouter.handle(url)
    }
}

enum AuthRoute: Equatable {
    case login
    case registration
}

struct CinematicSplashView: View {
    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            CompactLivingBackdrop(primary: Cinema2026.accent, secondary: Cinema2026.amber)
            VStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Text("Plink")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
            }
        }
    }
}

extension Notification.Name {
    static let plinkSignedOut = Notification.Name("plinkSignedOut")
    static let plinkRoomCreated = Notification.Name("plinkRoomCreated")
}
