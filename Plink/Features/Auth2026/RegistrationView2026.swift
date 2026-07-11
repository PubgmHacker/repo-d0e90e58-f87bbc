// Plink/Features/Auth2026/RegistrationView2026.swift — §8 Final Unified
//
// Cinematic registration with poster mosaic. Uses existing AuthService.

import SwiftUI

struct RegistrationView2026: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptsTerms = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onRegistered: () -> Void
    let onLogin: () -> Void

    private var canRegister: Bool {
        !displayName.isEmpty &&
        username.count >= 3 &&
        email.contains("@") &&
        password.count >= 6 &&
        acceptsTerms
    }

    private var passwordIssues: [String] {
        var issues: [String] = []
        if password.count < 6 { issues.append("Минимум 6 символов") }
        if !password.contains(where: { $0.isNumber }) { issues.append("Минимум 1 цифра") }
        return issues
    }

    var body: some View {
        CinematicAuthContainer(title: "Создать аккаунт") {
            VStack(spacing: 10) {
                CompactAuthField(title: "Имя", text: $displayName, contentType: .name)
                CompactAuthField(title: "Username", text: $username, contentType: .username)
                CompactAuthField(title: "Email", text: $email, contentType: .emailAddress)
                CompactAuthField(title: "Пароль", text: $password, contentType: .newPassword, secure: true)

                if !passwordIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(passwordIssues, id: \.self) { issue in
                            HStack(spacing: 4) {
                                Image(systemName: "circle")
                                    .font(.system(size: 8))
                                Text(issue)
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(Cinema2026.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle(isOn: $acceptsTerms) {
                    Text("Принимаю Условия и Политику")
                        .font(.caption)
                        .foregroundStyle(Cinema2026.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Cinema2026.danger)
                }

                Button {
                    Task { await register() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(Cinema2026.background) }
                        Text("Создать аккаунт")
                    }
                }
                .buttonStyle(AuthPrimaryButtonStyle())
                .disabled(!canRegister || isLoading)

                HStack(spacing: 4) {
                    Text("Уже есть аккаунт?")
                        .foregroundStyle(Cinema2026.secondary)
                    Button("Войти", action: onLogin)
                        .fontWeight(.semibold)
                }
                .font(.footnote)

                LegalConsentFooter()
                    .padding(.top, 8)
            }
        }
    }

    private func register() async {
        isLoading = true
        errorMessage = nil
        do {
            let authService = AuthService(api: apiClient)
            _ = try await authService.signUp(email: email, password: password, username: username)
            // Save token to Keychain
            if let token = authService.authToken {
                KeychainHelper.save(token, for: "rave_auth_token")
            }
            onRegistered()
        } catch {
            errorMessage = "Ошибка регистрации. Попробуйте другой username или email."
        }
        isLoading = false
    }
}
