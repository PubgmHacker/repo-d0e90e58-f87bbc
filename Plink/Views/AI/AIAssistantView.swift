// Plink/Views/AI/AIAssistantView.swift — GPT-5.6 V4 Rescue §6
//
// Replaced old generic assistant with PlinkAIMeshView + PlinkAIChatView.
// Uses V4Surface with .ai surface for living background.

import SwiftUI

struct AIAssistantView: View {
    @Environment(PlinkThemeStore.self) private var themeStore
    @State private var model = PlinkAIViewModel()
    @State private var input = ""

    var body: some View {
        V4Surface(theme: themeStore.appTheme, surface: .ai) {
            VStack(spacing: 0) {
                // AI Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ИИ-помощник")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Cinema2026.text)
                        Text(stateText)
                            .font(.system(size: 14))
                            .foregroundStyle(Cinema2026.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // AI Mesh
                PlinkAIMeshView(
                    state: model.visualState,
                    theme: themeStore.appTheme
                )
                .frame(height: 220)
                .padding(.vertical, 16)

                // Chat
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.messages) { msg in
                            HStack {
                                if msg.role == .user { Spacer() }
                                Text(msg.text)
                                    .font(.system(size: 15))
                                    .foregroundStyle(msg.role == .user ? .white : Cinema2026.text)
                                    .padding(12)
                                    .background(
                                        msg.role == .user ? Cinema2026.accent : Cinema2026.surface,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                if msg.role != .user { Spacer() }
                            }
                        }
                    }
                    .padding(16)
                }

                // Composer
                HStack(spacing: 10) {
                    TextField("Спросите ИИ...", text: $input)
                        .textFieldStyle(RaveTextFieldStyle())
                    Button {
                        let text = input
                        input = ""
                        Task { await model.send(text) }
                    } label: {
                        Image(systemName: model.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Cinema2026.accent)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading)
                }
                .padding(16)
            }
        }
    }

    private var stateText: String {
        switch model.visualState {
        case .idle: "Готов помочь с выбором"
        case .listening: "Слушаю..."
        case .thinking: "Анализирую..."
        case .speaking: "Отвечаю..."
        case .moderating: "Модерация активна"
        case .offline: "Недоступен"
        case .failed: "Ошибка"
        }
    }
}
