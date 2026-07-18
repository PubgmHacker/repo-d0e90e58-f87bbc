'use client';

import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { dictionaries, type Dictionary, type Locale } from '@/lib/i18n/dictionaries';

const I18nContext = createContext<{ locale: Locale; t: Dictionary; setLocale: (l: Locale) => void } | null>(null);

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>('ru');

  useEffect(() => {
    const saved = localStorage.getItem('plink-locale') as Locale | null;
    if (saved === 'ru' || saved === 'en') setLocaleState(saved);
  }, []);

  const setLocale = (l: Locale) => {
    setLocaleState(l);
    localStorage.setItem('plink-locale', l);
    document.documentElement.lang = l;
  };

  return (
    <I18nContext.Provider value={{ locale, t: dictionaries[locale], setLocale }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error('useI18n outside provider');
  return ctx;
}