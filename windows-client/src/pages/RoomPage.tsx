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
  const [chatOpen, setChatOpen] = useState(true);
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
    <div className="cinematic-room">
      <div className="player-stage">
        {embedUrl ? (
          <iframe
            className="player-iframe"
            title={room.name}
            src={embedUrl}
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowFullScreen
          />
        ) : (
          <div className="player-placeholder">No video selected</div>
        )}

        {/* Glass overlay — horizontal player ref */}
        <div className="player-overlay">
          <div className="player-top-bar glass-pill">
            <button type="button" className="overlay-btn" onClick={onLeave} aria-label="Close">✕</button>
            <span className="overlay-title">{room.name}</span>
            <div className="overlay-top-actions">
              {onPopOut && (
                <button type="button" className="overlay-btn" onClick={onPopOut}>Pop out</button>
              )}
              <span className={`sync-pill ${connected ? 'live' : ''}`}>
                {connected ? 'Synced' : 'Connecting…'}
              </span>
            </div>
          </div>

          <div className="player-bottom glass-pill">
            <div className="player-meta">
              <strong>{room.name}</strong>
              <span className="muted">Code {room.code}</span>
            </div>
            <div className="player-progress">
              <div className="progress-track"><div className="progress-fill" style={{ width: '35%' }} /></div>
            </div>
            <div className="player-pills">
              <button type="button" className="meta-pill" onClick={() => setChatOpen((o) => !o)}>
                Chat {messages.length > 0 && `(${messages.length})`}
              </button>
              <button type="button" className="meta-pill">Participants ({participants.length})</button>
              <button type="button" className="meta-pill">Sync</button>
            </div>
          </div>
        </div>
      </div>

      {error && <p className="error banner room-error">{error}</p>}

      <aside className={`room-chat-panel ${chatOpen ? 'open' : ''}`}>
        <header className="chat-panel-header">
          <h4>Live chat</h4>
          <button type="button" className="overlay-btn" onClick={() => setChatOpen(false)}>✕</button>
        </header>
        <div className="presence-bar">
          {participants.map((p) => (
            <span key={p.userId} className="presence-chip">
              {p.avatarURL ? <img src={p.avatarURL} alt="" /> : <span>{p.username[0]}</span>}
              {p.username}
            </span>
          ))}
        </div>
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
            placeholder="Message…"
          />
          <button type="submit" className="pro-btn primary">Send</button>
        </form>
      </aside>
    </div>
  );
}