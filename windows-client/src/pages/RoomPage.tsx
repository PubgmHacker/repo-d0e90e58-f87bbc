import { useEffect, useMemo, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import { api } from '../lib/api';
import { PlinkRealtimeClient } from '../lib/websocket';
import type { ChatMessage, Room } from '../lib/types';
import { EmojiPicker } from '../components/chat/EmojiPicker';
import { findEmojiById, type EmojiItem } from '../lib/emojiManifest';

type Props = {
  room: Room;
  userId: string;
  onLeave: () => void;
  onPopOut?: () => void;
};

/**
 * RoomPage — 1:1 with iOS WatchRoomScreen.
 * Layout (portrait-style, like iOS):
 * ┌────────────────────────────────────┐
 * │ Header: ← | Room name | actions    │
 * ├────────────────────────────────────┤
 * │ Player (16:9)                      │
 * ├────────────────────────────────────┤
 * │ Presence bar (avatars + count)     │
 * ├────────────────────────────────────┤
 * │ Chat list (scrollable)             │
 * ├────────────────────────────────────┤
 * │ Composer (emoji btn + input + send)│
 * └────────────────────────────────────┘
 */
export function RoomPage({ room, userId, onLeave, onPopOut }: Props) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [participants, setParticipants] = useState<
    Array<{ userId: string; username: string; avatarURL?: string }>
  >([]);
  const [connected, setConnected] = useState(false);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const [showEmojiPicker, setShowEmojiPicker] = useState(false);
  const clientRef = useRef<PlinkRealtimeClient | null>(null);
  const chatListRef = useRef<HTMLDivElement>(null);
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

  // Auto-scroll to bottom on new message
  useEffect(() => {
    if (chatListRef.current) {
      chatListRef.current.scrollTop = chatListRef.current.scrollHeight;
    }
  }, [messages]);

  function sendMessage(e?: FormEvent) {
    e?.preventDefault();
    const text = draft.trim();
    if (!text) return;
    clientRef.current?.sendChat(text);
    setDraft('');
  }

  function handleEmojiPick(emoji: EmojiItem) {
    if (emoji.src) {
      // Custom emoji — insert as :emoji_id:
      setDraft((prev) => `${prev}:${emoji.id}: `);
    } else {
      // Unicode emoji
      setDraft((prev) => `${prev}${emoji.id} `);
    }
    setShowEmojiPicker(false);
  }

  // Render message text with inline custom emoji
  function renderMessageContent(text: string) {
    const parts = text.split(/(:\w+:)/g);
    return parts.map((part, i) => {
      const match = part.match(/^:(\w+):$/);
      if (match) {
        const emoji = findEmojiById(match[1]);
        if (emoji) {
          return (
            <img
              key={i}
              src={emoji.src}
              alt={emoji.name}
              className="inline-emoji"
            />
          );
        }
      }
      return <span key={i}>{part}</span>;
    });
  }

  return (
    <div className="watch-room">
      {/* Header */}
      <header className="watch-room-header">
        <button type="button" className="back-btn" onClick={onLeave}>
          ← Назад
        </button>
        <span className="watch-room-title">{room.name}</span>
        <div className="watch-room-actions">
          {onPopOut && (
            <button type="button" className="back-btn" onClick={onPopOut}>
              Pop out
            </button>
          )}
          <span className={`back-btn ${connected ? 'active' : ''}`}>
            {connected ? '● Synced' : '○ Connecting…'}
          </span>
        </div>
      </header>

      {/* Player */}
      <div className="player-stage">
        {embedUrl ? (
          <iframe
            title={room.name}
            src={embedUrl}
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowFullScreen
          />
        ) : (
          <div className="player-placeholder">No video selected</div>
        )}
      </div>

      {/* Presence bar */}
      <div className="presence-bar">
        <div className="presence-avatars">
          {participants.slice(0, 5).map((p) => (
            <div key={p.userId} className="presence-avatar" title={p.username}>
              {p.avatarURL ? (
                <img src={p.avatarURL} alt={p.username} style={{ width: '100%', height: '100%', borderRadius: '50%', objectFit: 'cover' }} />
              ) : (
                <span>{p.username[0]?.toUpperCase()}</span>
              )}
            </div>
          ))}
          {participants.length > 5 && (
            <div className="presence-avatar">+{participants.length - 5}</div>
          )}
        </div>
        <span className="presence-count">
          {participants.length} {participants.length === 1 ? 'человек' : 'чел.'} смотрят
        </span>
        <div className="presence-actions">
          <button type="button" className="mic-btn" title="Микрофон">
            🎤
          </button>
          <button type="button" className="cam-btn" title="Камера">
            📹
          </button>
        </div>
      </div>

      {/* Chat region */}
      <div className="chat-region">
        {error && <p className="error banner" style={{ margin: '12px 20px' }}>{error}</p>}

        <div className="chat-list" ref={chatListRef}>
          {messages.length === 0 && (
            <div className="empty-state">
              <h3>Сообщений пока нет</h3>
              <p>Напиши первым — начни беседу!</p>
            </div>
          )}
          {messages.map((m) => {
            const isOutgoing = m.senderID === userId;
            const participant = participants.find((p) => p.userId === m.senderID);
            const authorName = participant?.username ?? 'Unknown';
            const avatar = participant?.avatarURL;
            return (
              <div key={m.id} className={`chat-bubble ${isOutgoing ? 'outgoing' : ''}`}>
                <div className="chat-bubble-avatar">
                  {avatar ? (
                    <img src={avatar} alt={authorName} />
                  ) : (
                    <span>{authorName[0]?.toUpperCase()}</span>
                  )}
                </div>
                <div className="chat-bubble-content">
                  {!isOutgoing && <div className="chat-bubble-author">{authorName}</div>}
                  <div className="chat-bubble-text">{renderMessageContent(m.text)}</div>
                </div>
              </div>
            );
          })}
        </div>

        {/* Composer with emoji picker */}
        <form className="chat-composer" onSubmit={(e) => sendMessage(e)}>
          <button
            type="button"
            className={`composer-emoji-btn ${showEmojiPicker ? 'active' : ''}`}
            onClick={() => setShowEmojiPicker((s) => !s)}
            title="Emoji"
          >
            😊
          </button>
          <input
            className="composer-input"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Сообщение…"
            autoFocus
          />
          <button
            type="submit"
            className="send-btn"
            disabled={!draft.trim()}
            title="Отправить"
          >
            ➤
          </button>

          {showEmojiPicker && (
            <EmojiPicker
              isPremium={false /* TODO: get from user */}
              onPick={handleEmojiPick}
              onClose={() => setShowEmojiPicker(false)}
            />
          )}
        </form>
      </div>
    </div>
  );
}
