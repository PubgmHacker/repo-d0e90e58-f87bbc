import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import type { Room } from '../lib/types';
import { LivingBackdrop } from '../components/cinema/LivingBackdrop';
import { HomeSkeleton } from '../components/ui/Skeleton';

type Props = {
  onOpenRoom: (room: Room) => void;
  onCreate: () => void;
};

export function RoomsPage({ onOpenRoom, onCreate }: Props) {
  const [rooms, setRooms] = useState<Room[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [code, setCode] = useState('');
  const [joining, setJoining] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        setRooms(await api.getRooms());
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Load failed');
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  async function joinByCode() {
    const c = code.trim().toUpperCase();
    if (!c || joining) return;
    setJoining(true);
    setError('');
    try {
      onOpenRoom(await api.joinRoom(c));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Join failed');
    } finally {
      setJoining(false);
    }
  }

  if (loading) return <HomeSkeleton />;

  return (
    <div className="cinema-page">
      <LivingBackdrop />
      <div className="cinema-page-inner">
        <header className="cinema-page-head">
          <h2>Комнаты</h2>
          <button type="button" className="cinema-btn cinema-btn-round cinema-btn-accent" onClick={onCreate} aria-label="Создать">
            +
          </button>
        </header>

        <div className="rooms-join-row glass-surface">
          <input
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="Код комнаты"
            maxLength={12}
            onKeyDown={(e) => e.key === 'Enter' && joinByCode()}
          />
          <button type="button" className="cinema-btn cinema-btn-accent" onClick={joinByCode} disabled={joining || !code.trim()}>
            {joining ? '…' : 'Войти'}
          </button>
        </div>

        {error && <p className="error banner">{error}</p>}

        {rooms.length === 0 ? (
          <div className="cinema-empty glass-surface">
            <p>Нет активных комнат</p>
            <button type="button" className="cinema-btn cinema-btn-accent" onClick={onCreate}>Создать комнату</button>
          </div>
        ) : (
          <div className="rooms-list">
            {rooms.map((room) => (
              <button key={room.id} type="button" className="room-list-row glass-surface" onClick={() => onOpenRoom(room)}>
                <div className="room-list-thumb">
                  {room.mediaItem?.thumbnailURL ? (
                    <img src={room.mediaItem.thumbnailURL} alt="" />
                  ) : (
                    <div className="live-room-placeholder" />
                  )}
                  {room.isActive && <span className="live-room-badge">LIVE</span>}
                </div>
                <div className="room-list-meta">
                  <strong>{room.name}</strong>
                  <span>{room.mediaItem?.title ?? 'Без видео'}</span>
                  <span className="muted">{room.hostName} · {room.code}</span>
                </div>
                <span className="room-list-chevron">›</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}