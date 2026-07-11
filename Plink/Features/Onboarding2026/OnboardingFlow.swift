// Plink/Features/Onboarding2026/OnboardingFlow.swift — §9 Final Unified
//
// Three-page onboarding: value → services → room.
// No paywall or permissions inside onboarding.

import SwiftUI

struct OnboardingPageModel: Identifiable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let body: LocalizedStringKey
}

struct OnboardingFlow: View {
    let onFinish: () -> Void
    let onSkip: (() -> Void)?

    @State private var selection = 0

    private let pages: [OnboardingPageModel] = [
        .init(id: "together", symbol: "person.3.fill",
              title: "Кино становится ближе",
              body: "Создавайте комнаты и смотрите синхронно с друзьями."),
        .init(id: "services", symbol: "rectangle.stack.fill",
              title: "Выберите, где смотреть",
              body: "Сначала создайте комнату, затем выберите сервис и контент."),
        .init(id: "room", symbol: "bubble.left.and.bubble.right.fill",
              title: "Всё важное рядом",
              body: "Участники, чат и точная синхронизация остаются вокруг видео."),
    ]

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            CompactLivingBackdrop(primary: Cinema2026.accent, secondary: Cinema2026.amber)

            VStack(spacing: 0) {
                // Skip button (only on non-last pages, if onSkip provided)
                if let onSkip, selection < pages.count - 1 {
                    HStack {
                        Spacer()
                        Button("Пропустить", action: onSkip)
                            .font(.caption)
                            .foregroundStyle(Cinema2026.secondary)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                } else {
                    Color.clear.frame(height: 48)
                }

                // Page content
                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPage(page: page).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Progress dots
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? Cinema2026.text : Cinema2026.divider)
                            .frame(width: index == selection ? 22 : 7, height: 7)
                    }
                }

                // CTA
                Button(selection == pages.count - 1 ? "Начать" : "Далее") {
                    if selection == pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) { selection += 1 }
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.background)
                .frame(maxWidth: .infinity)
                .frame(height: CompactPhoneMetrics.primaryButtonHeight)
                .background(Cinema2026.text, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 22)
            }
        }
    }
}

struct OnboardingPage: View {
    let page: OnboardingPageModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: page.symbol)
                .font(.system(size: 64))
                .foregroundStyle(Cinema2026.accent)

            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Cinema2026.text)
                .multilineTextAlignment(.center)

            Text(page.body)
                .font(.system(size: 15))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
