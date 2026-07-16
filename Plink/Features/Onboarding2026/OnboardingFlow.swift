// Plink/Features/Onboarding2026/OnboardingFlow.swift — 4-step MVP onboarding
// Cinema2026 chrome only; no V4 home redesign.

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [OnboardingPageModel] = [
        .init(id: "sync", symbol: "play.circle.fill",
              title: "Смотрите вместе",
              body: "YouTube, VK, Rutube — синхронно с друзьями. Медиана ~300 мс."),
        .init(id: "ai", symbol: "sparkles",
              title: "AI Companion",
              body: "Подскажет, что включить, и поможет создать комнату."),
        .init(id: "themes", symbol: "moon.stars.fill",
              title: "Живые темы",
              body: "Aurora, Cosmos, Verdant, Magma — атмосфера комнаты в Plink+."),
        .init(id: "cross", symbol: "iphone.gen3",
              title: "Все экраны",
              body: "iOS, Android, Mac, Windows — один код комнаты на всех."),
    ]

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            CompactLivingBackdrop(primary: Cinema2026.accent, secondary: Cinema2026.amber)

            VStack(spacing: 0) {
                if let onSkip, selection < pages.count - 1 {
                    HStack {
                        Spacer()
                        Button("Пропустить", action: onSkip)
                            .font(.caption)
                            .foregroundStyle(Cinema2026.secondary)
                            .accessibilityLabel("Пропустить онбординг")
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                } else {
                    Color.clear.frame(height: 48)
                }

                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPage(page: page).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? Cinema2026.text : Cinema2026.divider)
                            .frame(width: index == selection ? 22 : 7, height: 7)
                    }
                }
                .accessibilityLabel("Шаг \(selection + 1) из \(pages.count)")

                Button(selection == pages.count - 1 ? "Начать" : "Далее") {
                    if selection == pages.count - 1 {
                        onFinish()
                    } else if reduceMotion {
                        selection += 1
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
                .accessibilityLabel(selection == pages.count - 1 ? "Начать" : "Далее")
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
                .accessibilityHidden(true)
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
