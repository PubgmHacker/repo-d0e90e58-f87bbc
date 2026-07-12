// Plink/Views/Home/JoinRoomView.swift — GPT-5.6 V4 §7

import SwiftUI

struct JoinRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlinkThemeStore.self) private var themeStore
    @State private var code = ""

    var body: some View {
        V4SecondaryScreen(surface: .rooms, title: "Войти в комнату", dismiss: dismiss.callAsFunction) {
            VStack(spacing: 20) {
                V4ScreenHeader(eyebrow: "ПРИГЛАШЕНИЕ", title: "Введите код")
                TextField("Код комнаты", text: $code)
                    .textInputAutocapitalization(.characters)
                    .textContentType(.oneTimeCode)
                    .v4InputStyle()
                Button("Продолжить") { }
                    .buttonStyle(V4PrimaryButtonStyle())
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Сканировать QR-код") { }
                    .buttonStyle(V4SecondaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)
        }
    }
}
