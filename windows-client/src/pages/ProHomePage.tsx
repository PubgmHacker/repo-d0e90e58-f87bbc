import { useEffect, useRef, useState } from 'react';
import { api, youtubeMediaItem } from '../lib/api';
import type { Friend, Room, TrendingVideo } from '../lib/types';
import { IconPlay, IconPlus } from '../components/ui/Icons';
import { HomeSkeleton } from '../components/ui/Skeleton';

type HoverTarget =
  | { kind: 'room'; room: Room }
  | { kind: 'friend'; friend: Friend }
  | { kind: 'video'; video: TrendingVideo }
  | null;

type Props = {
  onOpenRoom: (room: Room) => void;
  onHoverChange: (target: HoverTarget) => void;
  onJoinPrompt: () => void;
};

// ════════════════════════════════════════════════════════════════════
// Hero video banners — 3 pre-loaded MP4 files
// ════════════════════════════════════════════════════════════════════
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

/**
 * ProHomePage — 1:1 with iOS V4HomeViewLive.
 * Sections:
 * 1. Hero Video Carousel (3 video banners with auto-scroll)
 * 2. Quick Room (быстрая комната)
 * 3. Популярное rail (horizontal scroll)
 * 4. Смотрят сейчас (active rooms)
 * 5. Друзья online
 */
export function ProHomePage({ onOpenRoom, onHoverChange, onJoinPrompt }: Props) {
  const [trending, setTrending] = useState<TrendingVideo[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [friends, setFriends] = useState<Friend[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      try {
        const [t, r, f] = await Promise.all([
          api.getTrending(),
          api.getRooms(),
          api.getFriends().catch(() => [] as Friend[]),
        ]);
        setTrending(t.results ?? []);
        setRooms(r ?? []);
        setFriends(f ?? []);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Load failed');
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  async function createFromVideo(video: TrendingVideo) {
    try {
      const room = await api.createRoom(
        video.title,
        youtubeMediaItem(video.id, video.title, video.thumbnailURL),
      );
      const joined = await api.joinRoom(room.code);
      onOpenRoom(joined);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Create failed');
    }
  }

  if (loading) return <HomeSkeleton />;

  const onlineFriends = friends.filter((f) => f.isOnline);
  const formatDuration = (s?: number) => {
    if (!s) return '';
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  return (
    <div className="discovery-home">
      {error && <p className="error banner">{error}</p>}

      {/* ═══ 1. Hero Video Carousel (3 banners with auto-scroll) ═══ */}
      <HeroVideoCarousel onJoinPrompt={onJoinPrompt} />

      {/* ═══ 2. Quick Room card ═══ */}
      <div className="quick-room-card">
        <div className="quick-room-glow" />
        <div className="quick-room-content">
          <div className="quick-room-icon">
            <IconPlus size={24} />
          </div>
          <div>
            <h3>Создать комнату</h3>
            <p>YouTube, VK, Rutube — синхронный просмотр с друзьями</p>
          </div>
          <button
            type="button"
            className="btn-primary"
            onClick={onJoinPrompt}
          >
            Создать
          </button>
        </div>
      </div>

      {/* ═══ 3. Популярное rail ═══ */}
      <section className="v4-rail">
        <div className="rail-header">
          <h2 className="rail-title">Популярное</h2>
          <button className="rail-see-all">Все →</button>
        </div>
        <div className="rail-scroll">
          {trending.slice(0, 12).map((v) => (
            <button
              key={v.id}
              type="button"
              className="rail-card"
              onClick={() => createFromVideo(v)}
              onMouseEnter={() => onHoverChange({ kind: 'video', video: v })}
            >
              <div className="rail-card-image">
                <img src={v.thumbnailURL} alt={v.title} />
                {v.duration && (
                  <span className="rail-card-duration">{formatDuration(v.duration)}</span>
                )}
              </div>
              <div className="rail-card-title">{v.title}</div>
              <div className="rail-card-channel">{v.channel}</div>
            </button>
          ))}
        </div>
      </section>

      {/* ═══ 4. Смотрят сейчас ═══ */}
      <section className="v4-rail">
        <div className="rail-header">
          <h2 className="rail-title">Смотрят сейчас</h2>
          <button className="rail-see-all">Все →</button>
        </div>
        <div className="rail-scroll">
          {rooms.length === 0 ? (
            <div className="empty-state glass-panel" style={{ minWidth: 280 }}>
              <h3>Нет активных комнат</h3>
              <p>Создай первую из Популярного выше</p>
            </div>
          ) : (
            rooms.map((room) => {
              const participants = room.participants ?? [];
              return (
                <button
                  key={room.id}
                  type="button"
                  className="room-card"
                  onClick={() => onOpenRoom(room)}
                  onMouseEnter={() => onHoverChange({ kind: 'room', room })}
                >
                  <div className="room-card-poster">
                    <img
                      src={room.mediaItem?.thumbnailURL || '/favicon.svg' || undefined}
                      alt={room.name}
                    />
                    <div className="room-live-badge">
                      <span className="live-dot" /> LIVE
                    </div>
                    <div className="room-participants">
                      <div className="avatar-stack">
                        {participants.slice(0, 3).map((p, i) => (
                          <img
                            key={p.id}
                            src={p.avatarURL ?? undefined}
                            alt=""
                            style={{ marginLeft: i === 0 ? 0 : -8, zIndex: 3 - i }}
                          />
                        ))}
                        {participants.length > 3 && (
                          <span className="avatar-more">
                            +{participants.length - 3}
                          </span>
                        )}
                      </div>
                      <span className="room-count">
                        {participants.length} {participants.length === 1 ? 'человек' : 'чел.'}
                      </span>
                    </div>
                  </div>
                  <div className="room-card-title">{room.name}</div>
                  <div className="room-card-host">by {room.hostName}</div>
                </button>
              );
            })
          )}
        </div>
      </section>

      {/* ═══ 5. Друзья online ═══ */}
      {friends.length > 0 && (
        <section className="v4-rail">
          <div className="rail-header">
            <h2 className="rail-title">Друзья</h2>
            <span className="rail-count" style={{ color: 'var(--text-secondary)', fontSize: 13 }}>
              {onlineFriends.length} онлайн
            </span>
          </div>
          <div className="friends-row">
            {friends.map((f) => (
              <div
                key={f.id}
                className={`friend-card ${f.isOnline ? 'online' : ''}`}
                onMouseEnter={() => onHoverChange({ kind: 'friend', friend: f })}
              >
                <div className={`friend-avatar ${f.isOnline ? 'online' : ''}`}>
                  {f.avatarURL ? (
                    <img src={f.avatarURL} alt={f.username} />
                  ) : (
                    <span>{f.username[0]?.toUpperCase()}</span>
                  )}
                </div>
                <div className="friend-name">{f.username}</div>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Hero Video Carousel — auto-scrolling 3 video banners
// ════════════════════════════════════════════════════════════════════
function HeroVideoCarousel({ onJoinPrompt }: { onJoinPrompt: () => void }) {
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

  return (
    <section className="v4-hero" style={{ position: 'relative' }}>
      <div className="hero-backdrop">
        <video
          ref={videoRef}
          autoPlay
          loop
          muted
          playsInline
          poster={`/banners/hero_banner_${banner.id}_poster.png`}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            filter: 'brightness(0.7) saturate(1.1)',
          }}
        >
          <source src={`/banners/hero_banner_${banner.id}.mp4`} type="video/mp4" />
          <source src={`/banners/hero_banner_${banner.id}.webm`} type="video/webm" />
        </video>
        <div className="hero-gradient" />
      </div>

      {/* Dots indicator */}
      <div style={{
        position: 'absolute',
        top: 24,
        right: 24,
        zIndex: 3,
        display: 'flex',
        gap: 6,
      }}>
        {HERO_BANNERS.map((b, i) => (
          <button
            key={b.id}
            type="button"
            onClick={() => setCurrentIndex(i)}
            style={{
              width: i === currentIndex ? 24 : 8,
              height: 8,
              borderRadius: 4,
              border: 'none',
              background: i === currentIndex ? b.accent : 'rgba(255,255,255,0.3)',
              cursor: 'pointer',
              transition: 'all 0.3s',
            }}
            aria-label={`Banner ${i + 1}`}
          />
        ))}
      </div>

      <div className="hero-content">
        <span className="hero-badge">
          <span className="live-dot" /> PLINK+
        </span>
        <h1 className="hero-title">{banner.title}</h1>
        <p className="hero-channel" style={{ color: banner.accent }}>{banner.subtitle}</p>
        <div className="hero-actions">
          <button
            type="button"
            className="btn-primary"
            onClick={onJoinPrompt}
          >
            <IconPlay size={18} /> {banner.cta}
          </button>
          <button
            type="button"
            className="btn-secondary"
            onClick={onJoinPrompt}
          >
            Войти по коду
          </button>
        </div>
      </div>
    </section>
  );
}
