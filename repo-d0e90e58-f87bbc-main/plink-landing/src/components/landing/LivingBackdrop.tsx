'use client';

import { useEffect, useState, type CSSProperties } from 'react';
import { LIVE_THEMES } from '@/lib/liveThemes';

type Props = {
  animateThemes?: boolean;
};

export function LivingBackdrop({ animateThemes = true }: Props) {
  const [themeIdx, setThemeIdx] = useState(0);
  const [orbPhase, setOrbPhase] = useState(false);
  const theme = LIVE_THEMES[themeIdx]!;

  useEffect(() => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) return;
    const orbTimer = window.setInterval(() => setOrbPhase((p) => !p), 14000);
    return () => window.clearInterval(orbTimer);
  }, []);

  useEffect(() => {
    if (!animateThemes) return;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) return;
    const themeTimer = window.setInterval(() => {
      setThemeIdx((i) => (i + 1) % LIVE_THEMES.length);
    }, 16000);
    return () => window.clearInterval(themeTimer);
  }, [animateThemes]);

  return (
    <div
      className={`living-backdrop ${orbPhase ? 'living-phase-b' : 'living-phase-a'}`}
      aria-hidden
      style={{
        '--orb-primary': theme.primary,
        '--orb-secondary': theme.secondary,
      } as CSSProperties}
    >
      <div className="living-orb living-orb-a" />
      <div className="living-orb living-orb-b" />
      <div className="living-orb living-orb-c" />
      <div className="living-orb living-orb-d" />
      <span className="living-theme-chip">{theme.label}</span>
    </div>
  );
}