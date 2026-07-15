'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { useI18n } from '@/components/I18nProvider';

const platforms = [
  { id: 'ios', icon: '📱', size: '16 MB', req: 'iOS 17+', href: '/downloads/Plink.ipa' },
  { id: 'android', icon: '🤖', size: '28 MB', req: 'Android 7.0+', href: '/downloads/app-debug.apk' },
  { id: 'windows', icon: '🪟', size: '2 MB', req: 'Win 10+', href: '/downloads/Plink-1.0.0-x64-setup.exe' },
  { id: 'mac', icon: '🍎', size: '5 MB', req: 'macOS 13+', href: '/downloads/Plink-1.0.0-arm64.dmg' },
] as const;

const comparison = [
  ['YouTube', true, true, true, true],
  ['VK/Rutube', true, false, false, true],
  ['AI Companion', false, false, false, true],
  ['Living Themes', false, false, false, true],
  ['Windows native', false, false, true, true],
  ['Mac native', false, false, false, true],
];

export function HeroSection() {
  const { t } = useI18n();
  return (
    <section className="relative overflow-hidden pt-32 pb-20">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,rgba(99,102,241,0.25),transparent_55%)]" />
      <div className="relative mx-auto max-w-6xl px-4 text-center">
        <motion.h1
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-5xl font-bold leading-tight md:text-7xl lg:text-8xl"
        >
          {t.hero.title}<br />
          <span className="plink-gradient-text">{t.hero.title2}</span>
        </motion.h1>
        <p className="mx-auto mt-6 max-w-2xl text-lg text-[var(--plink-text-muted)]">{t.hero.subtitle}</p>
        <div className="mt-10 flex flex-wrap justify-center gap-4">
          <Link href="/download" className="rounded-full bg-[var(--plink-accent)] px-8 py-3 font-semibold hover:bg-[var(--plink-accent-glow)]">
            {t.hero.ctaIos}
          </Link>
          <Link href="/download#windows" className="rounded-full border border-white/20 px-8 py-3 font-semibold hover:bg-white/5">
            {t.hero.ctaWin}
          </Link>
        </div>
        <p className="mt-8 text-sm text-[var(--plink-text-muted)]">{t.hero.social}</p>
        <div className="plink-glow mx-auto mt-12 aspect-video max-w-4xl overflow-hidden rounded-2xl border border-white/10 bg-black">
          <div className="flex h-full items-center justify-center text-[var(--plink-text-muted)]">
            ▶ Sync demo — 3 devices watching together
          </div>
        </div>
      </div>
    </section>
  );
}

export function DownloadSection({ compact = false }: { compact?: boolean }) {
  const { t } = useI18n();
  const labels: Record<string, string> = {
    ios: t.download.ios, android: t.download.android, windows: t.download.windows, mac: t.download.mac,
  };

  return (
    <section id="download" className={`py-20 ${compact ? '' : 'bg-[var(--plink-bg-light)]'}`}>
      <div className="mx-auto max-w-6xl px-4">
        <h2 className="text-center text-3xl font-bold md:text-4xl">{t.download.title}</h2>
        <p className="mt-2 text-center text-[var(--plink-text-muted)]">{t.download.subtitle}</p>
        <div className="mt-12 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {platforms.map((p) => (
            <motion.div
              key={p.id}
              id={p.id === 'windows' ? 'windows' : undefined}
              whileHover={{ y: -4 }}
              className="glass rounded-2xl p-6 text-center"
            >
              <div className="text-4xl">{p.icon}</div>
              <h3 className="mt-4 text-lg font-semibold">{labels[p.id]}</h3>
              <p className="mt-1 text-sm text-[var(--plink-text-muted)]">{p.size}</p>
              <p className="text-xs text-[var(--plink-text-muted)]">{p.req}</p>
              <a
                href={p.href}
                className="mt-6 inline-block w-full rounded-xl bg-[var(--plink-accent)] py-2 text-sm font-semibold hover:bg-[var(--plink-accent-glow)]"
              >
                {t.download.download}
              </a>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}

export function FeaturesSection() {
  const { t } = useI18n();
  const items = [t.features.ai, t.features.themes, t.features.chat, t.features.voice, t.features.services, t.features.sync];
  return (
    <section className="py-20">
      <h2 className="text-center text-3xl font-bold">{t.features.title}</h2>
      <div className="mx-auto mt-12 grid max-w-6xl gap-6 px-4 sm:grid-cols-2 lg:grid-cols-3">
        {items.map((item) => (
          <div key={item.title} className="glass rounded-2xl p-6">
            <h3 className="text-lg font-semibold">{item.title}</h3>
            <p className="mt-2 text-sm text-[var(--plink-text-muted)]">{item.desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

export function HowItWorksSection() {
  const { t } = useI18n();
  const steps = [
    { n: '1', title: t.how.s1, desc: t.how.s1d },
    { n: '2', title: t.how.s2, desc: t.how.s2d },
    { n: '3', title: t.how.s3, desc: t.how.s3d },
  ];
  return (
    <section className="bg-[var(--plink-bg-light)] py-20">
      <h2 className="text-center text-3xl font-bold">{t.how.title}</h2>
      <div className="mx-auto mt-12 grid max-w-6xl gap-8 px-4 md:grid-cols-3">
        {steps.map((s) => (
          <div key={s.n} className="text-center">
            <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-[var(--plink-accent)] text-lg font-bold">{s.n}</div>
            <h3 className="mt-4 font-semibold">{s.title}</h3>
            <p className="mt-2 text-sm text-[var(--plink-text-muted)]">{s.desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

export function ComparisonSection() {
  const { t } = useI18n();
  return (
    <section className="py-20">
      <h2 className="text-center text-3xl font-bold">{t.compare.title}</h2>
      <div className="mx-auto mt-10 max-w-4xl overflow-x-auto px-4">
        <table className="w-full min-w-[520px] text-left text-sm">
          <thead>
            <tr className="border-b border-white/10 text-[var(--plink-text-muted)]">
              <th className="py-3">Feature</th>
              <th>Rave</th><th>Teleparty</th><th>Kast</th><th className="text-[var(--plink-accent-glow)]">Plink</th>
            </tr>
          </thead>
          <tbody>
            {comparison.map(([name, ...vals]) => (
              <tr key={String(name)} className="border-b border-white/5">
                <td className="py-3">{name}</td>
                {vals.map((v, i) => (
                  <td key={i} className={i === 3 ? 'text-[var(--plink-accent-glow)]' : ''}>{v ? '✅' : '❌'}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export function PlusSection() {
  const { t } = useI18n();
  return (
    <section className="bg-[var(--plink-bg-light)] py-20">
      <div className="mx-auto max-w-4xl px-4 text-center">
        <h2 className="text-3xl font-bold">{t.plus.title}</h2>
        <p className="mt-2 text-[var(--plink-text-muted)]">{t.plus.subtitle}</p>
        <div className="mt-10 grid gap-6 md:grid-cols-3">
          {[t.plus.m1, t.plus.m3, t.plus.m12].map((price) => (
            <div key={price} className="glass rounded-2xl p-6">
              <p className="text-2xl font-bold plink-gradient-text">{price}</p>
              <Link href="/plink-plus" className="mt-4 inline-block rounded-xl border border-white/20 px-6 py-2 text-sm hover:bg-white/5">
                Get
              </Link>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export function TestimonialsSection() {
  const { t, locale } = useI18n();
  const quotes = locale === 'ru'
    ? [
        { text: 'Plink изменил то, как мы смотрим кино с друзьями. AI-компаньон — гениально!', author: 'Анна К., Москва' },
        { text: 'Наконец приложение, которое работает на iPhone, Windows и Mac.', author: 'Дмитрий П., СПб' },
      ]
    : [
        { text: 'Plink changed how I watch movies with friends. The AI companion is genius!', author: 'Anna K., Moscow' },
        { text: 'Finally an app that works on iPhone, Windows, and Mac.', author: 'Dmitry P., Saint Petersburg' },
      ];
  return (
    <section className="py-20">
      <h2 className="text-center text-3xl font-bold">{t.testimonials.title}</h2>
      <div className="mx-auto mt-10 grid max-w-4xl gap-6 px-4 md:grid-cols-2">
        {quotes.map((q) => (
          <blockquote key={q.author} className="glass rounded-2xl p-6 text-sm">
            <p className="italic text-[var(--plink-text-muted)]">&ldquo;{q.text}&rdquo;</p>
            <footer className="mt-4 font-medium">— {q.author}</footer>
          </blockquote>
        ))}
      </div>
    </section>
  );
}

export function CookieBanner() {
  const { t } = useI18n();
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    if (!localStorage.getItem('plink-cookie-ok')) setVisible(true);
  }, []);
  if (!visible) return null;
  return (
    <div className="fixed bottom-4 left-4 right-4 z-50 mx-auto max-w-lg glass rounded-xl p-4 text-sm md:left-auto">
      <p>{t.cookie}</p>
      <button
        type="button"
        className="mt-3 rounded-lg bg-[var(--plink-accent)] px-4 py-1.5 text-xs font-semibold"
        onClick={() => { localStorage.setItem('plink-cookie-ok', '1'); setVisible(false); }}
      >
        {t.accept}
      </button>
    </div>
  );
}