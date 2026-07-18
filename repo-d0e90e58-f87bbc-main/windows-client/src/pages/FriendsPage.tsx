import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import type { Friend } from '../lib/types';
import { LivingBackdrop } from '../components/cinema/LivingBackdrop';
import { HomeSkeleton } from '../components/ui/Skeleton';

export function FriendsPage() {
  const [friends, setFriends] = useState<Friend[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      try {
        setFriends(await api.getFriends());
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Load failed');
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  if (loading) return <HomeSkeleton />;

  return (
    <div className="cinema-page">
      <LivingBackdrop />
      <div className="cinema-page-inner">
        <header className="cinema-page-head">
          <h2>Друзья</h2>
          <span className="cinema-rail-count">{friends.filter((f) => f.isOnline).length} онлайн</span>
        </header>

        {error && <p className="error banner">{error}</p>}

        {friends.length === 0 ? (
          <div className="cinema-empty glass-surface">
            <p>Пока нет друзей — пригласите по коду комнаты</p>
          </div>
        ) : (
          <div className="friends-page-list">
            {friends.map((f) => (
              <div key={f.id} className="friend-list-row glass-surface">
                {f.avatarURL ? <img src={f.avatarURL} alt="" className="friend-list-avatar" /> : (
                  <span className="friend-list-avatar">{f.username[0]}</span>
                )}
                <div>
                  <strong>{f.username}</strong>
                  <span className={`status-pill ${f.isOnline ? 'online' : 'offline'}`}>
                    {f.isOnline ? 'Online' : 'Away'}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}