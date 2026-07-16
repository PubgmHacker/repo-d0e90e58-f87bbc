'use client';

import Link from 'next/link';
import { useI18n } from '@/components/I18nProvider';
import { BackgroundVideo } from './BackgroundVideo';
import { DeviceMockup } from './DeviceMockup';
import { RaveBottomBanner } from './RaveBottomBanner';
import { ServicesMarquee } from './ServicesMarquee';
import { LINKS } from '@/lib/downloads';

type Platform = {
  id: string;
  variant: 'mac' | 'iphone' | 'android' | 'windows';
  href: string;
  external?: boolean;
  hintKey: 'clickToDownload' | 'appStore';
};

const ROWS: Platform[][] = [
  [
    { id: 'mac', variant: 'mac', href: LINKS.mac, hintKey: 'clickToDownload' },
    { id: 'ios', variant: 'iphone', href: LINKS.appStore, external: true, hintKey: 'appStore' },
  ],
  [
    { id: 'android', variant: 'android', href: LINKS.androidApk, hintKey: 'clickToDownload' },
    { id: 'windows', variant: 'windows', href: LINKS.windows, hintKey: 'clickToDownload' },
  ],
];

function PlatformIcon({ id }: { id: string }) {
  if (id === 'windows') {
    return (
      <svg className="rave-platform-icon" viewBox="0 0 448 512" aria-hidden>
        <path d="M0 93.7l183.6-25.3v177.4H0V93.7zm0 324.6l183.6 25.3V268.4H0v149.9zm203.8 28L448 480V268.4H203.8v177.9zm0-380.6v180.1H448V32L203.8 65.7z" fill="currentColor" />
      </svg>
    );
  }
  if (id === 'android') {
    return (
      <svg className="rave-platform-icon" viewBox="0 0 512 512" aria-hidden>
        <path d="M325.3 234.3L104.6 13l280.8 161.2-60.1 60.1zM47 0C34 6.8 25.3 19.2 25.3 35.3v441.3c0 16.1 8.7 28.5 21.7 35.3l256.6-256L47 0zm425.2 225.6l-58.9-34.1-65.7 64.5 65.7 64.5 60.1-34.1c18-14.3 18-46.5-1.2-60.8zM104.6 499l280.8-161.2-60.1-60.1L104.6 499z" fill="currentColor" />
      </svg>
    );
  }
  return (
    <svg className="rave-platform-icon" viewBox="0 0 384 512" aria-hidden>
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" fill="currentColor" />
    </svg>
  );
}

function PlatformCard({ platform, label, hint }: { platform: Platform; label: string; hint: string }) {
  const inner = (
    <>
      <DeviceMockup variant={platform.variant} />
      <h3 className="rave-hero-label">
        <PlatformIcon id={platform.id} />
        {label}
      </h3>
      <span className="rave-dl-hint">{hint}</span>
    </>
  );

  if (platform.external) {
    return (
      <a href={platform.href} className="rave-device" target="_blank" rel="noopener noreferrer">
        {inner}
      </a>
    );
  }

  return (
    <a
      href={platform.href}
      className="rave-device"
      download={platform.id === 'android' || platform.id === 'windows'}
    >
      {inner}
    </a>
  );
}

export function RaveLanding() {
  const { t, locale, setLocale } = useI18n();
  const labels: Record<string, string> = {
    mac: t.download.mac,
    ios: t.download.ios,
    android: t.download.android,
    windows: t.download.windows,
  };

  return (
    <div className="rave-page">
      <BackgroundVideo />

      <header className="rave-header">
        <Link href="/" className="rave-logo">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/img/plink-logo-mark.png" alt="" className="rave-logo-img" width={36} height={36} />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/img/plink-logo-wordmark.png" alt="Plink" className="rave-logo-wordmark" height={22} />
        </Link>
        <nav className="rave-nav">
          <Link href="/features">{t.nav.features}</Link>
          <Link href="/plink-plus">{t.nav.plus}</Link>
          <Link href="/download">{t.nav.download}</Link>
          <button
            type="button"
            onClick={() => setLocale(locale === 'ru' ? 'en' : 'ru')}
            className="rave-lang-btn"
          >
            {locale === 'ru' ? 'EN' : 'RU'}
          </button>
        </nav>
      </header>

      <main className="rave-hero">
        <div className="rave-hero-copy">
          <h1 className="rave-title">{t.rave.watchTogether}</h1>
          <p className="rave-tagline">{t.rave.tagline}</p>
          <p className="rave-social-proof">{t.hero.social}</p>
        </div>

        <div className="rave-mockups">
          {ROWS.map((row, i) => (
            <div
              key={i}
              className={`rave-device-group${i === 0 ? ' rave-device-group-top' : ' rave-device-group-bottom'}`}
            >
              {row.map((p) => (
                <PlatformCard
                  key={p.id}
                  platform={p}
                  label={labels[p.id]}
                  hint={p.hintKey === 'appStore' ? t.rave.appStore : t.rave.clickToDownload}
                />
              ))}
            </div>
          ))}
        </div>

        <ServicesMarquee />

        <div className="rave-highlights">
          {t.rave.highlights.map((item) => (
            <div key={item} className="rave-highlight-pill">{item}</div>
          ))}
        </div>
      </main>

      <footer className="rave-footer">
        <div className="rave-footer-grid">
          <div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/img/plink-logo-white.png" alt="Plink" className="rave-footer-logo" height={28} />
            <p className="rave-footer-tagline">{t.footer.tagline}</p>
          </div>
          <div className="rave-footer-links">
            <Link href="/privacy">{t.nav.privacy}</Link>
            <Link href="/terms">{t.nav.terms}</Link>
            <Link href="/features">{t.nav.features}</Link>
            <Link href="/plink-plus">{t.nav.plus}</Link>
          </div>
        </div>
        <p className="rave-footer-copy">{t.footer.copy}</p>
      </footer>

      <RaveBottomBanner />
    </div>
  );
}