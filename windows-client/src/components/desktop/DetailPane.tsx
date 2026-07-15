import type { Friend, Room, TrendingVideo } from '../../lib/types';

export type DetailTarget =
  | { kind: 'room'; room: Room }
  | { kind: 'friend'; friend: Friend }
  | { kind: 'video'; video: TrendingVideo }
  | null;

type Props = {
  target: DetailTarget;
  onJoinRoom?: (room: Room) => void;
};

export function DetailPane({ target, onJoinRoom }: Props) {
  if (!target) {
    return (
      <div className="detail-empty">
        <p className="muted">Hover a room, friend, or video for preview</p>
      </div>
    );
  }

  if (target.kind === 'room') {
    const { room } = target;
    return (
      <div className="detail-content">
        <h4>{room.name}</h4>
        <p className="muted">Host: {room.hostName}</p>
        <p>Code: <strong>{room.code}</strong></p>
        <p>{room.participantCount ?? '?'} watching</p>
        <button type="button" className="pro-btn primary" onClick={() => onJoinRoom?.(room)}>Join room</button>
      </div>
    );
  }

  if (target.kind === 'friend') {
    const { friend } = target;
    return (
      <div className="detail-content">
        <div className="detail-avatar">
          {friend.avatarURL ? <img src={friend.avatarURL} alt="" /> : <span>{friend.username[0]}</span>}
        </div>
        <h4>{friend.username}</h4>
        <p>{friend.isOnline ? 'Online' : 'Offline'}</p>
        <button type="button" className="pro-btn">Invite to room</button>
      </div>
    );
  }

  const { video } = target;
  return (
    <div className="detail-content">
      {video.thumbnailURL && <img className="detail-thumb" src={video.thumbnailURL} alt="" />}
      <h4>{video.title}</h4>
      <p className="muted">{video.channelTitle}</p>
      <button type="button" className="pro-btn primary">Create room</button>
    </div>
  );
}