// Plink/Features/Auth2026/AuthProviderButtons.swift — §8 Final Unified
//
// Reusable auth provider button components.

import SwiftUI
import AuthenticationServices

struct AppleSignInButton: View {
    let onResult: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            onResult(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: CompactPhoneMetrics.primaryButtonHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct GoogleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 18))
                Text("Продолжить с Google")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Cinema2026.text)
            .frame(maxWidth: .infinity)
            .frame(height: CompactPhoneMetrics.primaryButtonHeight)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
        }
    }
}
