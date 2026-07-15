import { useEffect, useState } from 'react';
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

/**
 * ProHomePage — 1:1 with iOS V4HomeViewLive.
 * Sections:
 * 1. V4 Hero (большое видео + Plink+ баннеры)
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

  const hero = trending[0];
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

      {/* ═══ 1. V4 Hero (как iOS V4Hero) ═══ */}
      {hero && (
        <section className="v4-hero" onClick={() => createFromVideo(hero)}>
          <div className="hero-backdrop">
            <img src={hero.thumbnailURL} alt={hero.title} />
            <div className="hero-gradient" />
          </div>

          <div className="hero-banners">
            <div className="banner banner-premium">
              ✨ Plink+ — Living themes, voice chat, custom emoji
            </div>
          </div>

          <div className="hero-content">
            <span className="hero-badge">
              <span className="live-dot" /> LIVE NOW
            </span>
            <h1 className="hero-title">{hero.title}</h1>
            <p className="hero-channel">{hero.channel}</p>
            <div className="hero-actions">
              <button
                type="button"
                className="btn-primary"
                onClick={(e) => { e.stopPropagation(); createFromVideo(hero); }}
              >
                <IconPlay size={18} /> Смотреть вместе
              </button>
              <button
                type="button"
                className="btn-secondary"
                onClick={(e) => { e.stopPropagation(); onJoinPrompt(); }}
              >
                Войти по коду
              </button>
            </div>
          </div>
        </section>
      )}

      {/* ═══ 2. Quick Room card (как iOS "Быстрая комната") ═══ */}
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

      {/* ═══ 3. Популярное rail (как iOS "Популярное") ═══ */}
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

      {/* ═══ 4. Смотрят сейчас (как iOS active rooms rail) ═══ */}
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
