import { useEffect, useState } from 'react';
import { api, youtubeMediaItem } from '../lib/api';
import type { Friend, Room, TrendingVideo } from '../lib/types';
import { IconPlay, IconSearch } from '../components/ui/Icons';
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

export function ProHomePage({ onOpenRoom, onHoverChange, onJoinPrompt }: Props) {
  const [trending, setTrending] = useState<TrendingVideo[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [friends, setFriends] = useState<Friend[]>([]);
  const [search, setSearch] = useState('');
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
      const room = await api.createRoom(video.title, youtubeMediaItem(video.id, video.title, video.thumbnailURL));
      const joined = await api.joinRoom(room.code);
      onOpenRoom(joined);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Create failed');
    }
  }

  const filteredRooms = rooms.filter((r) => r.name.toLowerCase().includes(search.toLowerCase()));

  if (loading) return <HomeSkeleton />;

  const hero = trending[0];

  return (
    <div className="pro-home">
      <div className="pro-search-row">
        <div className="pro-search-wrap">
          <span className="search-icon"><IconSearch size={18} /></span>
          <input
            className="pro-search"
            placeholder="Search rooms, videos…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <button type="button" className="pro-btn" onClick={onJoinPrompt}>Join by code</button>
      </div>

      {error && <p className="error banner">{error}</p>}

      <section className="hero-banner">
        <div className="hero-video">
          {hero?.thumbnailURL && <img src={hero.thumbnailURL} alt="" />}
          <div className="hero-overlay">
            <h2>{hero?.title ?? 'Watch together with friends'}</h2>
            <p>{hero?.channelTitle ?? 'Pick a video and start a sync room in one click'}</p>
            {hero && (
              <button type="button" className="pro-btn primary" onClick={() => createFromVideo(hero)}>
                <IconPlay size={16} />
                Quick Room
              </button>
            )}
          </div>
        </div>
      </section>

      <div className="pro-columns">
        <section className="pro-column glass-panel">
          <h3 className="section-label">
            Trending
            <span className="count">{trending.length}</span>
          </h3>
          <div className="video-grid-pro">
            {trending.slice(0, 8).map((v) => (
              <button
                key={v.id}
                type="button"
                className="video-card-pro"
                onClick={() => createFromVideo(v)}
                onMouseEnter={() => onHoverChange({ kind: 'video', video: v })}
                onContextMenu={(e) => { e.preventDefault(); createFromVideo(v); }}
              >
                <div className="thumb-wrap">
                  {v.thumbnailURL && <img src={v.thumbnailURL} alt="" />}
                  <div className="play-badge"><span><IconPlay size={18} /></span></div>
                </div>
                <span className="card-title">{v.title}</span>
              </button>
            ))}
          </div>
        </section>

        <section className="pro-column glass-panel">
          <h3 className="section-label">
            Active Rooms
            <span className="count">{filteredRooms.length}</span>
          </h3>
          <div className="room-list-pro">
            {filteredRooms.length === 0 ? (
              <div className="empty-state">
                <p>No active rooms yet</p>
                <button type="button" className="pro-btn primary" onClick={() => hero && createFromVideo(hero)}>
                  Start watching
                </button>
              </div>
            ) : (
              filteredRooms.map((room) => (
                <button
                  key={room.id}
                  type="button"
                  className="room-card-pro"
                  onClick={() => onOpenRoom(room)}
                  onMouseEnter={() => onHoverChange({ kind: 'room', room })}
                >
                  <strong>{room.name}</strong>
                  <span className="room-meta">Host · {room.hostName}</span>
                  <span className="room-code">{room.code}</span>
                </button>
              ))
            )}
          </div>
        </section>

        <section className="pro-column glass-panel">
          <h3 className="section-label">
            Friends
            <span className="count">{friends.length}</span>
          </h3>
          <div className="friends-list-pro">
            {friends.length === 0 ? (
              <div className="empty-state">
                <p>Invite friends to watch together</p>
              </div>
            ) : (
              friends.map((f) => (
                <div
                  key={f.id}
                  className="friend-row-pro"
                  onMouseEnter={() => onHoverChange({ kind: 'friend', friend: f })}
                >
                  {f.avatarURL ? (
                    <img src={f.avatarURL} alt="" />
                  ) : (
                    <span className="avatar-fallback">{f.username[0]?.toUpperCase()}</span>
                  )}
                  <span className="friend-name">{f.username}</span>
                  <span className={`status-pill ${f.isOnline ? 'online' : 'offline'}`}>
                    {f.isOnline ? 'Online' : 'Away'}
                  </span>
                </div>
              ))
            )}
          </div>
        </section>
      </div>
    </div>
  );
}