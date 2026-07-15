import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { I18nProvider } from '@/components/I18nProvider';
import { CookieBanner } from '@/components/landing/HomeSections';

const inter = Inter({ subsets: ['latin', 'cyrillic'], variable: '--font-inter' });

export const metadata: Metadata = {
  title: 'Plink — Watch together. Anywhere. Together.',
  description: 'Collaborative watching with AI companion. YouTube, VK, Rutube sync across iOS, Android, Windows, and Mac.',
  openGraph: {
    title: 'Plink — Watch together',
    description: 'Sync playback, chat, and react with friends. AI companion included.',
    url: 'https://plink.vercel.app',
    siteName: 'Plink',
    type: 'website',
    locale: 'ru_RU',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Plink — Watch together',
    description: 'Collaborative watching with AI companion',
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ru">
      <body className={`${inter.variable} antialiased`}>
        <I18nProvider>
          {children}
          <CookieBanner />
        </I18nProvider>
      </body>
    </html>
  );
}