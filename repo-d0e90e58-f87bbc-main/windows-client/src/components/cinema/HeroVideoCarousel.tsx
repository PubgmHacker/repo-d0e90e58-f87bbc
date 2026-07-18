import { useEffect, useRef, useState } from 'react';

/**
 * HeroVideoCarousel — auto-scrolling 3 video banners.
 * 1:1 with iOS HeroVideoCarousel + Android HeroVideoCarousel.
 *
 * Banners (pre-loaded in /public/banners/):
 * 1. Watch Together (1.5 MB) — friends on couch
 * 2. AI Companion (2.2 MB) — futuristic AI orb
 * 3. Sync Devices (1.7 MB) — 3 devices with sync lines
 */

const HERO_BANNERS = [
  {
    id: 'watch_together',
    title: 'Смотрим вместе',
    subtitle: 'Watch together. Anywhere. Together.',
    accent: '#2DE2E6',
    cta: 'Смотреть вместе',
  },
  {
    id: 'ai_companion',
    title: 'AI Companion',
    subtitle: 'Умный помощник для совместного просмотра',
    accent: '#26D9A4',
    cta: 'Plink+',
  },
  {
    id: 'sync_devices',
    title: 'Синхронный просмотр',
    subtitle: 'Sync ±2s across iOS, Android, Mac, Windows',
    accent: '#0EB5C9',
    cta: 'Скачать',
  },
] as const;

interface Props {
  onJoinPrompt?: () => void;
  onWatchTogether?: () => void;
}

export function HeroVideoCarousel({ onJoinPrompt, onWatchTogether }: Props) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const videoRef = useRef<HTMLVideoElement>(null);

  // Auto-scroll every 6 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentIndex((prev) => (prev + 1) % HERO_BANNERS.length);
    }, 6000);
    return () => clearInterval(interval);
  }, []);

  // Play video when banner changes
  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.load();
      videoRef.current.play().catch(() => {
        // Autoplay blocked — will play on user interaction
      });
    }
  }, [currentIndex]);

  const banner = HERO_BANNERS[currentIndex];

  const handlePrimaryClick = () => {
    if (banner.id === 'sync_devices') {
      // Open downloads page
      window.open('/download', '_self');
    } else if (banner.id === 'ai_companion') {
      // Plink+ paywall
      onJoinPrompt?.();
    } else {
      // Watch together → create room
      onWatchTogether?.() ?? onJoinPrompt?.();
    }
  };

  return (
    <section className="hero-video-carousel">
      <div className="hero-video-backdrop">
        <video
          ref={videoRef}
          autoPlay
          loop
          muted
          playsInline
          poster={`/banners/hero_banner_${banner.id}_poster.png`}
        >
          <source src={`/banners/hero_banner_${banner.id}.mp4`} type="video/mp4" />
          <source src={`/banners/hero_banner_${banner.id}.webm`} type="video/webm" />
        </video>
        <div className="hero-video-gradient" />
      </div>

      {/* Dots indicator */}
      <div className="hero-video-dots">
        {HERO_BANNERS.map((b, i) => (
          <button
            key={b.id}
            type="button"
            onClick={() => setCurrentIndex(i)}
            className={`hero-video-dot ${i === currentIndex ? 'active' : ''}`}
            style={i === currentIndex ? { background: b.accent, width: 24 } : undefined}
            aria-label={`Banner ${i + 1}`}
          />
        ))}
      </div>

      <div className="hero-video-content">
        <span className="hero-video-badge">
          <span className="live-dot" /> PLINK+
        </span>
        <h1 className="hero-video-title">{banner.title}</h1>
        <p className="hero-video-subtitle" style={{ color: banner.accent }}>
          {banner.subtitle}
        </p>
        <div className="hero-video-actions">
          <button type="button" className="hero-video-primary" onClick={handlePrimaryClick}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
              <path d="M8 5v14l11-7z" />
            </svg>
            {banner.cta}
          </button>
          <button
            type="button"
            className="hero-video-secondary"
            onClick={onJoinPrompt}
          >
            Войти по коду
          </button>
        </div>
      </div>
    </section>
  );
}
