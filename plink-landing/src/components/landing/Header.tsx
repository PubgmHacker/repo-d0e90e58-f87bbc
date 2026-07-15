'use client';

import Link from 'next/link';
import { useI18n } from '@/components/I18nProvider';

export function Header() {
  const { locale, setLocale, t } = useI18n();

  return (
    <header className="fixed top-0 z-50 w-full glass">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4">
        <Link href="/" className="text-xl font-bold tracking-tight">
          <span className="plink-gradient-text">Plink</span>
        </Link>
        <nav className="hidden gap-6 text-sm text-[var(--plink-text-muted)] md:flex">
          <Link href="/features" className="hover:text-white">{t.nav.features}</Link>
          <Link href="/download" className="hover:text-white">{t.nav.download}</Link>
          <Link href="/plink-plus" className="hover:text-white">{t.nav.plus}</Link>
        </nav>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => setLocale(locale === 'ru' ? 'en' : 'ru')}
            className="rounded-full border border-white/10 px-3 py-1 text-xs uppercase tracking-wide text-[var(--plink-text-muted)] hover:border-white/30"
          >
            {locale === 'ru' ? 'EN' : 'RU'}
          </button>
          <Link
            href="/download"
            className="rounded-full bg-[var(--plink-accent)] px-4 py-2 text-sm font-semibold text-white hover:bg-[var(--plink-accent-glow)]"
          >
            {t.nav.download}
          </Link>
        </div>
      </div>
    </header>
  );
}