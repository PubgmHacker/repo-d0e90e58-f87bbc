import { useEffect, useState } from 'react';
import { api, youtubeMediaItem } from '../lib/api';
import type { Friend, Room, TrendingVideo } from '../lib/types';

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

  if (loading) return <div className="pro-loading">Loading home…</div>;

  return (
    <div className="pro-home">
      <div className="pro-search-row">
        <input
          className="pro-search"
          placeholder="Search rooms, videos… (Ctrl+K)"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button type="button" className="pro-btn" onClick={onJoinPrompt}>Join by code</button>
      </div>

      {error && <p className="error banner">{error}</p>}

      <section className="hero-banner">
        <div className="hero-video">
          {trending[0]?.thumbnailURL && <img src={trending[0].thumbnailURL} alt="" />}
          <div className="hero-overlay">
            <h2>{trending[0]?.title ?? 'Watch together'}</h2>
            <button type="button" className="pro-btn primary" onClick={() => trending[0] && createFromVideo(trending[0])}>
              Quick Room
            </button>
          </div>
        </div>
      </section>

      <div className="pro-columns">
        <section className="pro-column">
          <h3>🔥 Trending</h3>
          <div className="video-grid-pro">
            {trending.slice(0, 9).map((v) => (
              <button
                key={v.id}
                type="button"
                className="video-card-pro"
                onClick={() => createFromVideo(v)}
                onMouseEnter={() => onHoverChange({ kind: 'video', video: v })}
                onContextMenu={(e) => { e.preventDefault(); createFromVideo(v); }}
              >
                {v.thumbnailURL && <img src={v.thumbnailURL} alt="" />}
                <span>{v.title}</span>
              </button>
            ))}
          </div>
        </section>

        <section className="pro-column">
          <h3>🎬 Active Rooms</h3>
          <div className="room-list-pro">
            {filteredRooms.length === 0 ? (
              <p className="muted">No active rooms</p>
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
                  <span>Code: {room.code}</span>
                  <span>{room.hostName}</span>
                </button>
              ))
            )}
          </div>
        </section>

        <section className="pro-column">
          <h3>👥 Friends</h3>
          <div className="friends-list-pro">
            {friends.length === 0 ? (
              <p className="muted">No friends yet</p>
            ) : (
              friends.map((f) => (
                <div
                  key={f.id}
                  className="friend-row-pro"
                  onMouseEnter={() => onHoverChange({ kind: 'friend', friend: f })}
                >
                  {f.avatarURL ? <img src={f.avatarURL} alt="" /> : <span className="avatar-fallback">{f.username[0]}</span>}
                  <span>{f.username}</span>
                  <span className={f.isOnline ? 'online-dot' : 'offline-dot'} />
                </div>
              ))
            )}
          </div>
        </section>
      </div>
    </div>
  );
}