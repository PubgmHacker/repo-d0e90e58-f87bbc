// Plink/Features/Auth2026/AuthEmailForm.swift — §8 Final Unified
//
// Email/password auth form used inside both Login and Registration.

import SwiftUI

struct AuthEmailForm: View {
    @Binding var email: String
    @Binding var password: String
    var passwordVisible: Bool = false
    var requiresRegistrationFields: Bool = false
    @Binding var displayName: String
    @Binding var username: String
    @Binding var acceptsTerms: Bool

    var body: some View {
        VStack(spacing: 10) {
            if requiresRegistrationFields {
                CompactAuthField(title: "Имя", text: $displayName, contentType: .name)
                CompactAuthField(title: "Username", text: $username, contentType: .username)
            }

            CompactAuthField(title: "Email", text: $email, contentType: .emailAddress)
            CompactAuthField(
                title: "Пароль",
                text: $password,
                contentType: requiresRegistrationFields ? .newPassword : .password,
                secure: !passwordVisible
            )

            if requiresRegistrationFields {
                Toggle(isOn: $acceptsTerms) {
                    Text("Принимаю Условия и Политику")
                        .font(.caption)
                        .foregroundStyle(Cinema2026.secondary)
                }
            }
        }
    }
}
