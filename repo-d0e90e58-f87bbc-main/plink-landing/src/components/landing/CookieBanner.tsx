'use client';

import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { useI18n } from '@/components/I18nProvider';

const HIDDEN_ON = new Set(['/', '/download']);

export function CookieBanner() {
  const { t } = useI18n();
  const pathname = usePathname();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (HIDDEN_ON.has(pathname)) return;
    if (!localStorage.getItem('plink-cookie-ok')) setVisible(true);
  }, [pathname]);

  if (!visible) return null;

  return (
    <div className="cookie-banner">
      <p>{t.cookie}</p>
      <button
        type="button"
        className="cookie-banner__btn"
        onClick={() => {
          localStorage.setItem('plink-cookie-ok', '1');
          setVisible(false);
        }}
      >
        {t.accept}
      </button>
    </div>
  );
}