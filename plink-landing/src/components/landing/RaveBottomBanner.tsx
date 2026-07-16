'use client';

import { useEffect, useState } from 'react';
import { useI18n } from '@/components/I18nProvider';
import { LINKS } from '@/lib/downloads';

const STORAGE_KEY = 'plink_bottom_banner_dismissed';

export function RaveBottomBanner() {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    try {
      const dismissed = localStorage.getItem(STORAGE_KEY);
      if (dismissed) {
        const ts = parseInt(dismissed, 10);
        if (Date.now() - ts < 72 * 60 * 60 * 1000) return;
      }
    } catch {
      /* ignore */
    }
    const timer = window.setTimeout(() => setOpen(true), 3200);
    return () => window.clearTimeout(timer);
  }, []);

  const dismiss = () => {
    setOpen(false);
    try {
      localStorage.setItem(STORAGE_KEY, String(Date.now()));
    } catch {
      /* ignore */
    }
  };

  if (!open) return null;

  return (
    <div className="plink-bottom-banner" role="dialog" aria-modal="true" onClick={dismiss}>
      <div className="plink-bottom-banner__card" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="plink-bottom-banner__close" aria-label="Close" onClick={dismiss}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" aria-hidden>
            <line x1="5" y1="5" x2="19" y2="19" />
            <line x1="19" y1="5" x2="5" y2="19" />
          </svg>
        </button>
        <div className="plink-bottom-banner__badge">
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden>
            <path fill="currentColor" d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
          </svg>
          App Store
        </div>
        <h2 className="plink-bottom-banner__heading">{t.rave.bannerTitle}</h2>
        <p className="plink-bottom-banner__body">{t.rave.bannerBody}</p>
        <a
          className="plink-bottom-banner__cta"
          href={LINKS.appStore}
          target="_blank"
          rel="noopener noreferrer"
        >
          {t.rave.bannerCta}
        </a>
        <button type="button" className="plink-bottom-banner__secondary" onClick={dismiss}>
          {t.rave.bannerDismiss}
        </button>
      </div>
    </div>
  );
}