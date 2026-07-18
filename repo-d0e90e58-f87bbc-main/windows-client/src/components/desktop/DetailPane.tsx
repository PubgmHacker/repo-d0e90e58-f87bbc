import type { Friend, Room, TrendingVideo } from '../../lib/types';
import { IconPlay } from '../ui/Icons';

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
        <p>Hover a room, video, or friend for preview</p>
      </div>
    );
  }

  if (target.kind === 'room') {
    const { room } = target;
    return (
      <div className="detail-content glass-panel">
        <span className="live-dot" />
        <h4>{room.name}</h4>
        <p className="muted">Host · {room.hostName}</p>
        <p className="room-code">{room.code}</p>
        <button type="button" className="pro-btn primary" onClick={() => onJoinRoom?.(room)}>Join room</button>
      </div>
    );
  }

  if (target.kind === 'friend') {
    const { friend } = target;
    return (
      <div className="detail-content glass-panel">
        <div className="detail-avatar">
          {friend.avatarURL ? <img src={friend.avatarURL} alt="" /> : <span>{friend.username[0]}</span>}
        </div>
        <h4>{friend.username}</h4>
        <span className={`status-pill ${friend.isOnline ? 'online' : 'offline'}`}>
          {friend.isOnline ? 'Online' : 'Away'}
        </span>
        <button type="button" className="pro-btn">Invite to room</button>
      </div>
    );
  }

  const { video } = target;
  return (
    <div className="detail-content glass-panel">
      {video.thumbnailURL && <img className="detail-thumb" src={video.thumbnailURL} alt="" />}
      <h4>{video.title}</h4>
      <p className="muted">{video.channelTitle}</p>
      <button type="button" className="pro-btn primary">
        <IconPlay size={14} />
        Create room
      </button>
    </div>
  );
}