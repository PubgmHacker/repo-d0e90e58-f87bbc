import type { Metadata } from 'next';
import { Fjalla_One, Inter, Poppins } from 'next/font/google';
import './globals.css';
import { I18nProvider } from '@/components/I18nProvider';
import { CookieBanner } from '@/components/landing/CookieBanner';

const inter = Inter({ subsets: ['latin', 'cyrillic'], variable: '--font-inter' });
const poppins = Poppins({ weight: ['400', '500', '600', '700'], subsets: ['latin', 'latin-ext'], variable: '--font-poppins' });
const fjalla = Fjalla_One({ weight: '400', subsets: ['latin', 'latin-ext'], variable: '--font-fjalla' });

export const metadata: Metadata = {
  title: 'Plink — Watch YouTube, Netflix, Disney+, and more with Friends!',
  description: 'Watch Together. Download Plink for Mac, iPhone, Android, and Windows.',
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
      <body className={`${inter.variable} ${poppins.variable} ${fjalla.variable} antialiased`}>
        <I18nProvider>
          {children}
          <CookieBanner />
        </I18nProvider>
      </body>
    </html>
  );
}