import { useEffect, useState } from 'react';
import { api, youtubeMediaItem } from '../lib/api';
import type { Friend, Room, TrendingVideo } from '../lib/types';
import { IconPlay, IconPlus } from '../components/ui/Icons';
import { HomeSkeleton } from '../components/ui/Skeleton';
import { detectPlatform } from '../lib/platform';

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

const GENRES = ['YouTube', 'Adventure', 'Together', 'Live'];

export function ProHomePage({ onOpenRoom, onHoverChange, onJoinPrompt }: Props) {
  const [trending, setTrending] = useState<TrendingVideo[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [friends, setFriends] = useState<Friend[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const isMac = detectPlatform() === 'mac';

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
      const room = await api.createRoom(video.title, youtubeMediaItem(video.id, video.title, video.thumbnailURL));
      const joined = await api.joinRoom(room.code);
      onOpenRoom(joined);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Create failed');
    }
  }

  const filteredRooms = rooms;
  if (loading) return <HomeSkeleton />;

  const hero = trending[0];
  const onlineFriends = friends.filter((f) => f.isOnline).length;

  return (
    <div className="discovery-home">
      {error && <p className="error banner">{error}</p>}

      {/* Hero — macOS Steam / Windows Disney+ style */}
      <section className={`hero-stage ${isMac ? 'hero-mac' : 'hero-win'}`}>
        <div className="hero-backdrop">
          {hero?.thumbnailURL && <img src={hero.thumbnailURL} alt="" />}
          <div className="hero-gradient" />
        </div>

        <div className="hero-content">
          <div className="hero-main">
            <div className="genre-pills">
              {GENRES.map((g) => (
                <span key={g} className="genre-pill">{g}</span>
              ))}
              <button type="button" className="genre-pill add" aria-label="Add tag"><IconPlus size={12} /></button>
            </div>
            <h1 className="hero-title">{hero?.title ?? 'Watch together'}</h1>
            <p className="hero-meta">
              {hero?.channelTitle && <span>{hero.channelTitle}</span>}
              <span className="match-badge">Live sync</span>
              {onlineFriends > 0 && <span>{onlineFriends} friends online</span>}
            </p>
            <div className="hero-actions">
              <button type="button" className="pro-btn primary hero-play" onClick={() => hero && createFromVideo(hero)}>
                <IconPlay size={18} />
                Play now
              </button>
              <button type="button" className="pro-btn" onClick={onJoinPrompt}>Join by code</button>
            </div>
          </div>

          {isMac && hero && (
            <aside className="hero-info-card glass-panel">
              <h3>{hero.title}</h3>
              <p className="muted">{hero.channelTitle ?? 'Trending on Plink'}</p>
              <div className="hero-info-actions">
                <button type="button" className="pro-btn primary" onClick={() => createFromVideo(hero)}>
                  Start room
                </button>
              </div>
              <div className="hero-thumbs">
                {trending.slice(1, 3).map((v) => (
                  <button key={v.id} type="button" className="hero-thumb" onClick={() => createFromVideo(v)}>
                    {v.thumbnailURL && <img src={v.thumbnailURL} alt="" />}
                  </button>
                ))}
              </div>
            </aside>
          )}
        </div>
      </section>

      {/* Horizontal rails — iOS Discovery + refs */}
      <section className="content-rail">
        <div className="rail-header">
          <h2>Trending</h2>
          <span className="rail-count">{trending.length}</span>
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
              <div className="rail-card-img">
                {v.thumbnailURL && <img src={v.thumbnailURL} alt="" />}
                <span className="rail-play"><IconPlay size={20} /></span>
              </div>
              <span className="rail-card-title">{v.title}</span>
            </button>
          ))}
        </div>
      </section>

      <section className="content-rail">
        <div className="rail-header">
          <h2>Active rooms</h2>
          <span className="rail-count">{filteredRooms.length}</span>
        </div>
        <div className="rail-scroll rooms-rail">
          {filteredRooms.length === 0 ? (
            <div className="empty-state glass-panel">
              <p>No active rooms — start one from Trending</p>
            </div>
          ) : (
            filteredRooms.map((room) => (
              <button
                key={room.id}
                type="button"
                className="room-rail-card glass-panel"
                onClick={() => onOpenRoom(room)}
                onMouseEnter={() => onHoverChange({ kind: 'room', room })}
              >
                <span className="live-dot" />
                <strong>{room.name}</strong>
                <span className="muted">{room.hostName}</span>
                <span className="room-code">{room.code}</span>
              </button>
            ))
          )}
        </div>
      </section>

      {friends.length > 0 && (
        <section className="content-rail">
          <div className="rail-header">
            <h2>Friends</h2>
            <span className="rail-count">{friends.length}</span>
          </div>
          <div className="friends-row">
            {friends.map((f) => (
              <div
                key={f.id}
                className="friend-chip glass-panel"
                onMouseEnter={() => onHoverChange({ kind: 'friend', friend: f })}
              >
                {f.avatarURL ? <img src={f.avatarURL} alt="" /> : <span>{f.username[0]}</span>}
                <span>{f.username}</span>
                <span className={`status-pill ${f.isOnline ? 'online' : 'offline'}`}>
                  {f.isOnline ? 'Online' : 'Away'}
                </span>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}