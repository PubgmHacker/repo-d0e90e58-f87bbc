// Plink/Features/Auth2026/LoginView2026.swift — §8 Final Unified
//
// Cinematic login with poster mosaic. Uses existing AuthService.

import SwiftUI
import AuthenticationServices

struct LoginView2026: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var email = ""
    @State private var password = ""
    @State private var showEmailForm = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onAuthenticated: () -> Void
    let onRegister: () -> Void

    var body: some View {
        CinematicAuthContainer(title: "Plink") {
            VStack(spacing: 10) {
                // Plink branding
                VStack(spacing: 4) {
                    Text("Plink")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(Cinema2026.text)
                    Text("Смотрите вместе")
                        .font(.system(size: 14))
                        .foregroundStyle(Cinema2026.secondary)
                }
                .padding(.bottom, 6)

                // Apple Sign-In (TODO: requires backend /api/auth/apple endpoint)
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: CompactPhoneMetrics.primaryButtonHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                AuthDivider(text: "или")
                    .padding(.vertical, 4)

                if showEmailForm {
                    CompactAuthField(title: "Email", text: $email, contentType: .emailAddress)
                    CompactAuthField(title: "Пароль", text: $password, contentType: .password, secure: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Cinema2026.danger)
                    }

                    Button {
                        Task { await signInWithEmail() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(Cinema2026.background) }
                            Text("Войти")
                        }
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                } else {
                    Button("Войти по email") {
                        showEmailForm = true
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                }

                HStack(spacing: 4) {
                    Text("Нет аккаунта?")
                        .foregroundStyle(Cinema2026.secondary)
                    Button("Создать", action: onRegister)
                        .fontWeight(.semibold)
                }
                .font(.footnote)

                LegalConsentFooter()
                    .padding(.top, 8)
            }
        }
    }

    private func signInWithEmail() async {
        isLoading = true
        errorMessage = nil
        do {
            let authService = AuthService(api: apiClient)
            _ = try await authService.signIn(email: email, password: password)
            // Save token to Keychain
            if let token = authService.authToken {
                KeychainHelper.save(token, for: "rave_auth_token")
            }
            onAuthenticated()
        } catch {
            errorMessage = "Ошибка входа. Проверьте email и пароль."
        }
        isLoading = false
    }

    /// Apple Sign-In handler.
    /// TODO: backend `/api/auth/apple` endpoint required to exchange identity token
    /// for a Plink JWT. Until then, show a friendly message.
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            errorMessage = "Вход через Apple скоро будет доступен. Используйте email."
        case .failure(let error):
            errorMessage = "Не удалось войти через Apple: \(error.localizedDescription)"
        }
    }
}
