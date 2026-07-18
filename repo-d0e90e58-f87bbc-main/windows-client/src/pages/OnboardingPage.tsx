import { useEffect, useState } from 'react';
import { analytics } from '../lib/analytics';
import { LivingBackdrop } from '../components/cinema/LivingBackdrop';

const STEPS = [
  {
    icon: '▶',
    title: 'Смотрите вместе',
    body: 'YouTube, VK, Rutube — синхронно с друзьями. Медиана ~350 мс.',
  },
  {
    icon: '✦',
    title: 'AI Companion',
    body: 'Подскажет, что включить, и поможет создать комнату.',
  },
  {
    icon: '☾',
    title: 'Живые темы',
    body: 'Aurora, Cosmos, Verdant, Magma — атмосфера комнаты в Plink+.',
  },
  {
    icon: '💻',
    title: 'Все экраны',
    body: 'iOS, Android, Mac, Windows — один код комнаты на всех.',
  },
] as const;

export const ONBOARDING_KEY = 'plink_onboarding_v3';

type Props = { onDone: () => void };

export function OnboardingPage({ onDone }: Props) {
  const [step, setStep] = useState(0);
  const current = STEPS[step]!;
  const isLast = step === STEPS.length - 1;

  useEffect(() => {
    analytics.onboardingStep(step);
  }, [step]);

  function finish(skipped: boolean) {
    if (skipped) analytics.onboardingSkipped(step);
    else analytics.onboardingComplete(step);
    localStorage.setItem(ONBOARDING_KEY, '1');
    onDone();
  }

  return (
    <div className="onboarding-overlay" role="dialog" aria-modal="true" aria-label="Онбординг Plink">
      <LivingBackdrop animateThemes />
      <div className="onboarding-card glass-surface">
        {!isLast && (
          <button type="button" className="onboarding-skip link-btn" onClick={() => finish(true)}>
            Пропустить
          </button>
        )}
        <div className="onboarding-icon" aria-hidden>
          {current.icon}
        </div>
        <h1>{current.title}</h1>
        <p className="muted">{current.body}</p>
        <div className="onboarding-dots" aria-label={`Шаг ${step + 1} из ${STEPS.length}`}>
          {STEPS.map((_, i) => (
            <span key={i} className={i === step ? 'is-active' : ''} />
          ))}
        </div>
        <button
          type="button"
          className="cinema-btn cinema-btn-light onboarding-cta"
          onClick={() => {
            if (isLast) finish(false);
            else setStep((s) => s + 1);
          }}
        >
          {isLast ? 'Начать' : 'Далее'}
        </button>
      </div>
    </div>
  );
}

export function needsOnboarding(): boolean {
  try {
    return localStorage.getItem(ONBOARDING_KEY) !== '1';
  } catch {
    return true;
  }
}
