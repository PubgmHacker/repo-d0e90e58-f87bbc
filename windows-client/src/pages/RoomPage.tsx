import { useEffect, useMemo, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import { api } from '../lib/api';
import { PlinkRealtimeClient } from '../lib/websocket';
import type { ChatMessage, Room } from '../lib/types';

type Props = {
  room: Room;
  userId: string;
  onLeave: () => void;
  onPopOut?: () => void;
};

export function RoomPage({ room, userId, onLeave, onPopOut }: Props) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [participants, setParticipants] = useState<Array<{ userId: string; username: string; avatarURL?: string }>>([]);
  const [connected, setConnected] = useState(false);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const clientRef = useRef<PlinkRealtimeClient | null>(null);
  const videoId = room.mediaItem?.videoId;

  const embedUrl = useMemo(() => {
    if (videoId) return `https://www.youtube.com/embed/${videoId}?autoplay=1`;
    return room.mediaItem?.streamURL;
  }, [room.mediaItem, videoId]);

  useEffect(() => {
    let active = true;
    const client = new PlinkRealtimeClient({
      onStateChange: (c) => active && setConnected(c),
      onMessage: (msg) => active && setMessages((prev) => [...prev, msg]),
      onError: (e) => active && setError(e),
    });
    clientRef.current = client;

    (async () => {
      try {
        if (!room.code) return;
        await api.joinRoom(room.code).catch(() => undefined);
        const [history, parts] = await Promise.all([
          api.getMessages(room.id),
          api.getParticipants(room.id),
        ]);
        if (!active) return;
        setMessages(history.messages ?? []);
        setParticipants(parts.participants ?? []);
        await client.connect(room.id);
      } catch (err) {
        if (active) setError(err instanceof Error ? err.message : 'Room connect failed');
      }
    })();

    return () => {
      active = false;
      client.disconnect();
      api.leaveRoom(room.id).catch(() => undefined);
    };
  }, [room.id, room.code]);

  function sendMessage(e: FormEvent) {
    e.preventDefault();
    const text = draft.trim();
    if (!text) return;
    clientRef.current?.sendChat(text);
    setDraft('');
  }

  return (
    <div className="page room-page">
      <header className="top-bar">
        <button onClick={onLeave}>← Назад</button>
        <div>
          <strong>{room.name}</strong>
          <span className="muted"> Код: {room.code}</span>
        </div>
        <div className="room-toolbar">
          {onPopOut && <button type="button" onClick={onPopOut} title="Mini player">Pop out</button>}
          <span className={connected ? 'status ok' : 'status'}>{connected ? 'Online' : 'Offline'}</span>
        </div>
      </header>

      {error && <p className="error banner">{error}</p>}

      <div className="room-layout">
        <div className="player-pane">
          {embedUrl ? (
            <iframe
              title={room.name}
              src={embedUrl}
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
            />
          ) : (
            <div className="player-placeholder">Видео не выбрано</div>
          )}
          <div className="presence-bar">
            {participants.map((p) => (
              <span key={p.userId} className="presence-chip">
                {p.avatarURL ? <img src={p.avatarURL} alt="" /> : <span className="avatar-fallback">{p.username[0]}</span>}
                {p.username}
              </span>
            ))}
          </div>
        </div>

        <aside className="chat-pane">
          <h4>Чат</h4>
          <div className="chat-messages">
            {messages.map((m) => (
              <div key={m.id} className={m.senderID === userId ? 'msg mine' : 'msg'}>
                <p>{m.text}</p>
              </div>
            ))}
          </div>
          <form className="chat-composer" onSubmit={sendMessage}>
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder="Сообщение..."
            />
            <button type="submit">→</button>
          </form>
        </aside>
      </div>
    </div>
  );
}