import { useEffect, useState } from 'react';
import { api, youtubeMediaItem } from '../lib/api';
import type { Room, TrendingVideo } from '../lib/types';

type Props = {
  onOpenRoom: (room: Room) => void;
  onOpenProfile: () => void;
};

export function HomePage({ onOpenRoom, onOpenProfile }: Props) {
  const [trending, setTrending] = useState<TrendingVideo[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [joinCode, setJoinCode] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      try {
        const [t, r] = await Promise.all([api.getTrending(), api.getRooms()]);
        setTrending(t.results ?? []);
        setRooms(r ?? []);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load');
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  async function createFromVideo(video: TrendingVideo) {
    setError('');
    try {
      const mediaItem = youtubeMediaItem(video.id, video.title, video.thumbnailURL);
      const room = await api.createRoom(video.title, mediaItem);
      const joined = await api.joinRoom(room.code);
      onOpenRoom(joined);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Create failed');
    }
  }

  async function joinByCode() {
    if (!joinCode.trim()) return;
    setError('');
    try {
      const room = await api.joinRoom(joinCode.trim().toUpperCase());
      onOpenRoom(room);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Join failed');
    }
  }

  if (loading) return <div className="page center">Загрузка...</div>;

  return (
    <div className="page home-page">
      <header className="top-bar">
        <h2>Plink</h2>
        <button onClick={onOpenProfile}>Профиль</button>
      </header>

      {error && <p className="error banner">{error}</p>}

      <section>
        <h3>Популярное</h3>
        <div className="video-grid">
          {trending.map((v) => (
            <button key={v.id} className="video-card" onClick={() => createFromVideo(v)}>
              {v.thumbnailURL && <img src={v.thumbnailURL} alt="" />}
              <span>{v.title}</span>
            </button>
          ))}
        </div>
      </section>

      <section>
        <h3>Войти по коду</h3>
        <div className="join-row">
          <input
            placeholder="ABCD12"
            value={joinCode}
            onChange={(e) => setJoinCode(e.target.value.toUpperCase())}
          />
          <button onClick={joinByCode}>Войти</button>
        </div>
      </section>

      <section>
        <h3>Активные комнаты</h3>
        {rooms.length === 0 ? (
          <p className="muted">Нет активных комнат</p>
        ) : (
          <div className="room-list">
            {rooms.map((room) => (
              <button key={room.id} className="room-card" onClick={() => onOpenRoom(room)}>
                <strong>{room.name}</strong>
                <span>Код: {room.code}</span>
                <span>{room.hostName}</span>
              </button>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}