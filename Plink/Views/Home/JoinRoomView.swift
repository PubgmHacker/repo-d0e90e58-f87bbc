// Plink/Views/Home/JoinRoomView.swift — simplified, no conflicting V4 types

import SwiftUI

struct JoinRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("ПРИГЛАШЕНИЕ")
                        .font(.caption2.bold())
                        .tracking(1.1)
                        .foregroundStyle(Cinema2026.accent)

                    Text("Введите код")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Cinema2026.text)

                    TextField("Код комнаты", text: $code)
                        .textInputAutocapitalization(.characters)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 16))
                        .foregroundStyle(Cinema2026.text)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))

                    Button("Продолжить") { }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16))
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Сканировать QR-код") { }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Cinema2026.divider, lineWidth: 0.5))
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
            }
            .navigationTitle("Войти в комнату")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}
