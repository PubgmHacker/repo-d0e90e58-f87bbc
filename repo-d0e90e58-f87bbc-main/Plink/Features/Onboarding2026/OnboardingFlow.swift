// Plink/Features/Onboarding2026/OnboardingFlow.swift — 4-step MVP onboarding
// Fixed: TabView no longer steals taps from Далее/Начать; callbacks always fire.

import SwiftUI

struct OnboardingPageModel: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let body: String
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

    private var isLast: Bool { selection >= pages.count - 1 }

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            CompactLivingBackdrop(primary: Cinema2026.accent, secondary: Cinema2026.amber)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Skip
                HStack {
                    Spacer()
                    if let onSkip, !isLast {
                        Button {
                            HapticManager.impact(.light)
                            onSkip()
                        } label: {
                            Text("Пропустить")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Cinema2026.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Пропустить онбординг")
                    }
                }
                .frame(height: 48)
                .padding(.horizontal, 12)

                // Pages — constrained so they cannot cover the bottom CTA
                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPage(page: page)
                            .tag(index)
                            .contentShape(Rectangle())
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Dots
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? Cinema2026.accent : Cinema2026.divider)
                            .frame(width: index == selection ? 22 : 7, height: 7)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selection)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
                .accessibilityLabel("Шаг \(selection + 1) из \(pages.count)")

                // CTA — outside TabView so hits always work
                Button {
                    HapticManager.impact(.medium)
                    advance()
                } label: {
                    Text(isLast ? "Начать" : "Далее")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .accessibilityLabel(isLast ? "Начать" : "Далее")
                .accessibilityAddTraits(.isButton)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if isLast {
            onFinish()
            return
        }
        let next = min(selection + 1, pages.count - 1)
        if reduceMotion {
            selection = next
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                selection = next
            }
        }
    }
}

struct OnboardingPage: View {
    let page: OnboardingPageModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            Image(systemName: page.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Cinema2026.accent)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Cinema2026.text)
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.system(size: 15))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
