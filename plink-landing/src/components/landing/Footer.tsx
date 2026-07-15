'use client';

import Link from 'next/link';
import { useI18n } from '@/components/I18nProvider';

export function Footer() {
  const { t } = useI18n();

  return (
    <footer className="border-t border-white/10 bg-[var(--plink-bg-light)] py-16">
      <div className="mx-auto grid max-w-6xl gap-10 px-4 md:grid-cols-4">
        <div>
          <p className="text-lg font-bold plink-gradient-text">Plink</p>
          <p className="mt-2 text-sm text-[var(--plink-text-muted)]">{t.footer.tagline}</p>
        </div>
        <div>
          <p className="mb-3 text-sm font-semibold">Product</p>
          <ul className="space-y-2 text-sm text-[var(--plink-text-muted)]">
            <li><Link href="/features">Features</Link></li>
            <li><Link href="/plink-plus">Pricing</Link></li>
            <li><Link href="/download">Download</Link></li>
          </ul>
        </div>
        <div>
          <p className="mb-3 text-sm font-semibold">Legal</p>
          <ul className="space-y-2 text-sm text-[var(--plink-text-muted)]">
            <li><Link href="/privacy">Privacy</Link></li>
            <li><Link href="/terms">Terms</Link></li>
          </ul>
        </div>
        <div>
          <p className="mb-3 text-sm font-semibold">Social</p>
          <ul className="space-y-2 text-sm text-[var(--plink-text-muted)]">
            <li><a href="https://t.me" target="_blank" rel="noreferrer">Telegram</a></li>
            <li><a href="https://discord.com" target="_blank" rel="noreferrer">Discord</a></li>
          </ul>
        </div>
      </div>
      <p className="mx-auto mt-10 max-w-6xl px-4 text-center text-xs text-[var(--plink-text-muted)]">
        {t.footer.copy}
      </p>
    </footer>
  );
}