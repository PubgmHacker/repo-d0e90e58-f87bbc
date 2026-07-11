// Plink/Features/Auth2026/AuthFlowModel.swift — §8 Final Unified
//
// Auth flow state machine. Manages login/registration routing,
// loading state, and error handling.

import Foundation
import Observation

@MainActor
@Observable
final class AuthFlowModel {
    enum Route: Equatable { case login, registration, emailLogin }

    var route: Route = .login
    var email = ""
    var password = ""
    var displayName = ""
    var username = ""
    var passwordVisible = false
    var acceptsTerms = false
    var isSubmitting = false
    var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var canRegister: Bool {
        !displayName.isEmpty &&
        username.count >= 3 &&
        email.contains("@") &&
        password.count >= 6 &&
        acceptsTerms
    }

    var passwordIssues: [String] {
        var issues: [String] = []
        if password.count < 6 { issues.append("Минимум 6 символов") }
        if !password.contains(where: { $0.isNumber }) { issues.append("Минимум 1 цифра") }
        return issues
    }

    var googleIsConfigured: Bool {
        // TODO: check if Google Sign-In is configured
        false
    }

    func signIn() async -> Bool {
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await authService.signIn(email: email, password: password)
            password = ""
            isSubmitting = false
            return true
        } catch {
            errorMessage = "Ошибка входа. Проверьте email и пароль."
            isSubmitting = false
            return false
        }
    }

    func register() async -> Bool {
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await authService.signUp(email: email, password: password, username: username)
            password = ""
            isSubmitting = false
            return true
        } catch {
            errorMessage = "Ошибка регистрации. Попробуйте другой username."
            isSubmitting = false
            return false
        }
    }

    func restoreSessionIfPossible() async -> Bool {
        // Check KeychainHelper for existing token
        return KeychainHelper.read(for: "rave_auth_token") != nil
    }
}
