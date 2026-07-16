'use client';

import { useI18n } from '@/components/I18nProvider';

const SERVICES = [
  'YouTube', 'Netflix', 'Disney+', 'HBO Max', 'VK Video', 'Rutube',
  'Twitch', 'Premier', 'Okko', 'Kinopoisk', 'IVI', 'Wink',
];

export function ServicesMarquee() {
  const { t } = useI18n();
  const items = [...SERVICES, ...SERVICES];

  return (
    <section className="rave-services-section" aria-label={t.rave.services}>
      <p className="rave-services-lead">{t.rave.services}</p>
      <div className="rave-marquee">
        <div className="rave-marquee__track">
          {items.map((name, i) => (
            <span key={`${name}-${i}`} className="rave-marquee__pill">{name}</span>
          ))}
        </div>
      </div>
    </section>
  );
}