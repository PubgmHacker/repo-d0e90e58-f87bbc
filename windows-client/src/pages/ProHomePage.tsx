import { useEffect, useMemo, useState } from 'react';
import { api, youtubeMediaItem } from '../lib/api';
import type { Friend, Room, TrendingVideo } from '../lib/types';
import { LivingBackdrop } from '../components/cinema/LivingBackdrop';
import {
  AIEntryCard,
  EditorialCollections,
  FriendsRail,
  HomeHeader,
  LiveRoomsRail,
  NetflixHero,
  StickyCreateCTA,
  TrendingRail,
} from '../components/cinema/HomeSections';
import { HomeSkeleton } from '../components/ui/Skeleton';

type Props = {
  onOpenRoom: (room: Room) => void;
  onJoinPrompt: () => void;
  onOpenAI: () => void;
};

export function ProHomePage({ onOpenRoom, onJoinPrompt, onOpenAI }: Props) {
  const [trending, setTrending] = useState<TrendingVideo[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [friends, setFriends] = useState<Friend[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError('');
      try {
        const [t, r, f] = await Promise.all([
          api.getTrending(),
          api.getRooms(),
          api.getFriends().catch(() => [] as Friend[]),
        ]);
        if (cancelled) return;
        setTrending(t.results ?? []);
        setRooms(r ?? []);
        setFriends(f ?? []);
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Load failed');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const recommended = useMemo(() => {
    if (trending.length <= 6) return [];
    return [...trending].sort(() => Math.random() - 0.5).slice(0, 10);
  }, [trending]);

  async function createFromVideo(video: TrendingVideo) {
    if (busy) return;
    setBusy(video.id);
    setError('');
    try {
      const room = await api.createRoom(video.title, youtubeMediaItem(video.id, video.title, video.thumbnailURL));
      const joined = await api.joinRoom(room.code);
      onOpenRoom(joined);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Create failed');
    } finally {
      setBusy(null);
    }
  }

  async function createFromHero() {
    const hero = trending[0];
    if (hero) await createFromVideo(hero);
    else onJoinPrompt();
  }

  if (loading) return <HomeSkeleton />;

  const hero = trending[0];

  return (
    <div className="cinema-home">
      <LivingBackdrop animateThemes />

      <div className="cinema-home-scroll">
        {error && <p className="error banner">{error}</p>}

        <HomeHeader />

        {hero ? (
          <NetflixHero video={hero} busy={busy === hero.id} onWatch={() => createFromVideo(hero)} />
        ) : (
          <div className="netflix-hero-skeleton glass-surface">Загрузка популярного…</div>
        )}

        <AIEntryCard onTap={onOpenAI} />

        <LiveRoomsRail rooms={rooms} onOpen={onOpenRoom} />

        <TrendingRail
          title="Популярное"
          videos={trending}
          busyId={busy}
          onSelect={createFromVideo}
        />

        {recommended.length > 0 && (
          <TrendingRail
            title="Рекомендуем"
            videos={recommended}
            busyId={busy}
            onSelect={createFromVideo}
          />
        )}

        <EditorialCollections videos={trending} busyId={busy} onSelect={createFromVideo} />

        <FriendsRail friends={friends} />

        {rooms.length === 0 && (
          <div className="cinema-empty glass-surface">
            <p>Нет активных комнат</p>
            <button type="button" className="cinema-btn cinema-btn-ghost" onClick={onJoinPrompt}>Войти по коду</button>
          </div>
        )}
      </div>

      <StickyCreateCTA busy={!!busy} onCreate={createFromHero} />
    </div>
  );
}