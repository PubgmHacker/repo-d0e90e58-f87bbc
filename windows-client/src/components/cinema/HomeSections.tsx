import type { Friend, Room, TrendingVideo } from '../../lib/types';
import { IconPlay, IconPlus, IconSparkles } from '../ui/Icons';

export function HomeHeader() {
  return (
    <header className="cinema-home-header">
      <div>
        <h1 className="cinema-home-title">Plink</h1>
        <p className="cinema-home-sub">Смотрите вместе</p>
      </div>
    </header>
  );
}

type HeroProps = {
  video: TrendingVideo;
  busy: boolean;
  onWatch: () => void;
};

export function NetflixHero({ video, busy, onWatch }: HeroProps) {
  const thumb = video.thumbnailURL ?? `https://img.youtube.com/vi/${video.id}/maxresdefault.jpg`;

  return (
    <section className="netflix-hero">
      <div className="netflix-hero-media" aria-hidden>
        <img
          src={thumb}
          alt=""
          onError={(e) => {
            e.currentTarget.src = `https://img.youtube.com/vi/${video.id}/hqdefault.jpg`;
          }}
        />
        <div className="netflix-hero-gradient" />
      </div>

      <div className="netflix-hero-body">
        <span className="live-eyebrow">● В ЭФИРЕ</span>
        <h2 className="netflix-hero-title">{video.title}</h2>
        <p className="netflix-hero-channel">{video.channelTitle}</p>
        <div className="netflix-hero-actions">
          <button type="button" className="cinema-btn cinema-btn-light" disabled={busy} onClick={onWatch}>
            <IconPlay size={14} />
            {busy ? 'Запуск…' : 'Смотреть вместе'}
          </button>
          <button type="button" className="cinema-btn cinema-btn-round" aria-label="Добавить">
            <IconPlus size={16} />
          </button>
        </div>
      </div>
    </section>
  );
}

type AIProps = { onTap: () => void };

export function AIEntryCard({ onTap }: AIProps) {
  return (
    <button type="button" className="ai-entry-card glass-surface" onClick={onTap}>
      <IconSparkles size={18} className="ai-entry-icon" />
      <span>Что посмотреть?</span>
      <span className="ai-entry-chevron">›</span>
    </button>
  );
}

type LiveRailProps = {
  rooms: Room[];
  onOpen: (room: Room) => void;
};

export function LiveRoomsRail({ rooms, onOpen }: LiveRailProps) {
  if (rooms.length === 0) return null;

  return (
    <section className="cinema-rail">
      <div className="cinema-rail-head">
        <h3>Сейчас смотрят</h3>
        <span className="cinema-rail-count">{rooms.length}</span>
      </div>
      <div className="cinema-rail-scroll">
        {rooms.map((room) => (
          <button key={room.id} type="button" className="live-room-card" onClick={() => onOpen(room)}>
            <div className="live-room-thumb">
              {room.mediaItem?.thumbnailURL ? (
                <img src={room.mediaItem.thumbnailURL} alt="" />
              ) : (
                <div className="live-room-placeholder" />
              )}
              <div className="live-room-gradient" />
              <span className="live-room-badge">LIVE</span>
            </div>
            <div className="live-room-meta">
              <strong>{room.name}</strong>
              <span>{room.hostName}</span>
              <span className="room-code-inline">{room.code}</span>
            </div>
          </button>
        ))}
      </div>
    </section>
  );
}

type TrendingProps = {
  title: string;
  videos: TrendingVideo[];
  busyId: string | null;
  onSelect: (video: TrendingVideo) => void;
};

export function TrendingRail({ title, videos, busyId, onSelect }: TrendingProps) {
  if (videos.length === 0) return null;

  return (
    <section className="cinema-rail">
      <div className="cinema-rail-head">
        <h3>{title}</h3>
        <span className="cinema-rail-count">{videos.length}</span>
      </div>
      <div className="cinema-rail-scroll">
        {videos.map((video) => (
          <button
            key={`${title}-${video.id}`}
            type="button"
            className="trending-card"
            disabled={busyId === video.id}
            onClick={() => onSelect(video)}
          >
            <div className="trending-poster">
              <img
                src={video.thumbnailURL ?? `https://img.youtube.com/vi/${video.id}/hqdefault.jpg`}
                alt=""
              />
            </div>
            <span className="trending-title">{video.title}</span>
            <span className="trending-channel">{video.channelTitle}</span>
          </button>
        ))}
      </div>
    </section>
  );
}

type EditorialProps = {
  videos: TrendingVideo[];
  busyId: string | null;
  onSelect: (video: TrendingVideo) => void;
};

const COLLECTIONS = ['Вечер с друзьями', 'Новинки недели', 'Для компании'];

export function EditorialCollections({ videos, busyId, onSelect }: EditorialProps) {
  if (videos.length < 3) return null;

  return (
    <section className="cinema-rail">
      <div className="cinema-rail-head">
        <h3>Подборки</h3>
      </div>
      <div className="cinema-rail-scroll editorial-scroll">
        {COLLECTIONS.map((name, idx) => {
          const video = videos[idx % videos.length]!;
          return (
            <button
              key={name}
              type="button"
              className="editorial-card"
              disabled={busyId === video.id}
              onClick={() => onSelect(video)}
            >
              <img src={video.thumbnailURL ?? `https://img.youtube.com/vi/${video.id}/hqdefault.jpg`} alt="" />
              <div className="editorial-overlay">
                <span className="editorial-eyebrow">Коллекция</span>
                <strong>{name}</strong>
              </div>
            </button>
          );
        })}
      </div>
    </section>
  );
}

type FriendsRailProps = { friends: Friend[] };

export function FriendsRail({ friends }: FriendsRailProps) {
  if (friends.length === 0) return null;

  return (
    <section className="cinema-rail">
      <div className="cinema-rail-head">
        <h3>Друзья</h3>
        <span className="cinema-rail-count">{friends.filter((f) => f.isOnline).length} онлайн</span>
      </div>
      <div className="friends-row">
        {friends.map((f) => (
          <div key={f.id} className="friend-chip glass-surface">
            {f.avatarURL ? <img src={f.avatarURL} alt="" /> : <span>{f.username[0]}</span>}
            <span>{f.username}</span>
            <span className={`status-pill ${f.isOnline ? 'online' : 'offline'}`}>
              {f.isOnline ? 'Online' : 'Away'}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

type StickyCTAProps = {
  busy: boolean;
  onCreate: () => void;
};

export function StickyCreateCTA({ busy, onCreate }: StickyCTAProps) {
  return (
    <div className="sticky-create-bar">
      <button type="button" className="cinema-btn cinema-btn-accent cinema-btn-wide" disabled={busy} onClick={onCreate}>
        <IconPlus size={16} />
        {busy ? 'Создаём…' : 'Создать комнату'}
      </button>
    </div>
  );
}