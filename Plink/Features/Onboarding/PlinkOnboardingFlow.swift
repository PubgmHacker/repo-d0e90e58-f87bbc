// Plink/Features/Onboarding/PlinkOnboardingFlow.swift — Onboarding
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §7

import SwiftUI

struct PlinkOnboardingFlow: View {
    enum Step: Int, CaseIterable { case value, room, start }

    @State private var step: Step = .value
    let onComplete: (OnboardingIntent) -> Void

    var body: some View {
        ZStack {
            CinemaColor.background.ignoresSafeArea()

            TabView(selection: $step) {
                OnboardingValuePage().tag(Step.value)
                OnboardingRoomPage().tag(Step.room)
                OnboardingStartPage(onComplete: onComplete).tag(Step.start)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                OnboardingProgress(current: step.rawValue, count: Step.allCases.count)
                if step != .start {
                    Button("Продолжить") {
                        withAnimation(.easeOut(duration: 0.28)) {
                            step = Step(rawValue: step.rawValue + 1) ?? .start
                        }
                    }
                    .buttonStyle(CinematicPrimaryButtonStyle())
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 40)
        }
    }
}

enum OnboardingIntent {
    case startWatching
    case joinRoom(String)
}

struct OnboardingValuePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 72))
                .foregroundStyle(CinemaColor.plink)
            Text("Смотрите вместе")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(CinemaColor.text)
            Text("Синхронизированное видео, общий чат и реакции. Как кинотеатр, но с друзьями.")
                .font(.system(size: 16))
                .foregroundStyle(CinemaColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

struct OnboardingRoomPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.system(size: 72))
                .foregroundStyle(CinemaColor.plink)
            Text("Создайте комнату")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(CinemaColor.text)
            Text("Выберите видео, пригласите друзей и наслаждайтесь вместе. Плей, пауза и перемотка синхронизированы.")
                .font(.system(size: 16))
                .foregroundStyle(CinemaColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

struct OnboardingStartPage: View {
    let onComplete: (OnboardingIntent) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 72))
                .foregroundStyle(CinemaColor.plink)
            Text("Готовы?")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(CinemaColor.text)
            Text("Начните смотреть вместе прямо сейчас.")
                .font(.system(size: 16))
                .foregroundStyle(CinemaColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
            Button("Начать") {
                onComplete(.startWatching)
            }
            .buttonStyle(CinematicPrimaryButtonStyle())
            .padding(.horizontal, 24)
        }
    }
}

struct OnboardingProgress: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? CinemaColor.plink : CinemaColor.raised)
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(CinemaMotion.standard, value: current)
            }
        }
        .padding(.bottom, 16)
    }
}
