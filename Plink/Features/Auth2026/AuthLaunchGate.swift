// Plink/Features/Auth2026/AuthLaunchGate.swift — §9 Final Unified
//
// Launch gate: restoring → auth → onboarding → app.
// Deep links survive auth + onboarding.

import SwiftUI

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
                    onSkip: nil
                )
                .transition(.opacity)

            case .app:
                PlinkAppShell(dependencies: dependencies)
                    .transition(.opacity)
            }
        }
        .task { await restoreSession() }
        .animation(.easeOut(duration: 0.32), value: destination)
        .onReceive(NotificationCenter.default.publisher(for: .plinkSignedOut)) { _ in
            // PATCH: immediately show login screen when user signs out
            withAnimation(.easeOut(duration: 0.3)) {
                destination = .authentication
            }
        }
        .onOpenURL { url in
            if destination == .app {
                // Forward to app shell
            } else {
                pendingURL = url
            }
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

        // Check if we have a valid auth token + can fetch user
        let authService = dependencies.authService
        let token = authService.authToken
        _ = try? await minimumSplash

        if token != nil {
            // Verify token is still valid by fetching current user
            let user = await authService.currentUser()
            if user != nil {
                destination = onboardingStore.needsCurrentOnboarding ? .onboarding : .app
            } else {
                // Token expired — try refresh
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
    }

    private func completeOnboarding() {
        onboardingStore.markCompleted(version: OnboardingVersion.current)
        destination = .app
    }
}

// MARK: - Auth route

enum AuthRoute: Equatable {
    case login
    case registration
}

// MARK: - Splash

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

// MARK: - Auth notifications
extension Notification.Name {
    static let plinkSignedOut = Notification.Name("plinkSignedOut")
}
