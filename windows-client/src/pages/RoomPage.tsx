import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import { api } from '../lib/api';
import { ClockSynchronizer } from '../lib/clockSync';
import { embedUrlForMedia } from '../lib/mediaUrl';
import { OrderedSyncController } from '../lib/syncController';
import { PlinkRealtimeClient } from '../lib/websocket';
import type { ChatMessage, Room } from '../lib/types';
import type { RoomState } from '../lib/syncTypes';
import { YouTubePlayer, type YouTubePlayerHandle } from '../components/player/YouTubePlayer';
import { EmbedPlayer } from '../components/player/EmbedPlayer';
import { analytics } from '../lib/analytics';

type Props = {
  room: Room;
  userId: string;
  onLeave: () => void;
  onPopOut?: () => void;
};

function formatTime(sec: number) {
  if (!Number.isFinite(sec) || sec < 0) return '0:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export function RoomPage({ room, userId, onLeave, onPopOut }: Props) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [participants, setParticipants] = useState<Array<{ userId: string; username: string; avatarURL?: string }>>([]);
  const [connected, setConnected] = useState(false);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const [chatOpen, setChatOpen] = useState(true);
  const [role, setRole] = useState<'host' | 'viewer'>(room.hostID === userId ? 'host' : 'viewer');
  const [playing, setPlaying] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [driftMs, setDriftMs] = useState(0);
  const [playerReady, setPlayerReady] = useState(false);

  const clientRef = useRef<PlinkRealtimeClient | null>(null);
  const ytRef = useRef<YouTubePlayerHandle>(null);
  const clockRef = useRef(new ClockSynchronizer());
  const syncRef = useRef<OrderedSyncController | null>(null);
  const applyingRemote = useRef(false);
  const lastHostPush = useRef(0);
  const roleRef = useRef(role);
  roleRef.current = role;

  const videoId = room.mediaItem?.videoId;
  const isYouTube = (room.mediaItem?.source === 'youtube' || !!videoId) && !!videoId
    && room.mediaItem?.source !== 'vk' && room.mediaItem?.source !== 'rutube';
  const fallbackEmbed = useMemo(
    () => (room.mediaItem ? embedUrlForMedia(room.mediaItem) : null),
    [room.mediaItem],
  );

  const isHost = role === 'host';

  const ensureSync = useCallback(() => {
    if (!syncRef.current) {
      syncRef.current = new OrderedSyncController(clockRef.current, {
        getPositionSec: () => ytRef.current?.getCurrentTime() ?? 0,
        getDurationSec: () => ytRef.current?.getDuration() ?? 0,
        isPlaying: () => ytRef.current?.isPlaying() ?? false,
        play: () => {
          applyingRemote.current = true;
          ytRef.current?.play();
          setPlaying(true);
          window.setTimeout(() => { applyingRemote.current = false; }, 300);
        },
        pause: () => {
          applyingRemote.current = true;
          ytRef.current?.pause();
          setPlaying(false);
          window.setTimeout(() => { applyingRemote.current = false; }, 300);
        },
        seek: (sec: number) => {
          applyingRemote.current = true;
          ytRef.current?.seek(sec);
          setPosition(sec);
          window.setTimeout(() => { applyingRemote.current = false; }, 300);
        },
      });
    }
    return syncRef.current;
  }, []);

  const pushHostState = useCallback((nextPlaying: boolean, nextPositionSec?: number) => {
    if (roleRef.current !== 'host' || !clientRef.current) return;
    const now = Date.now();
    if (now - lastHostPush.current < 120) return;
    lastHostPush.current = now;
    const pos = nextPositionSec ?? ytRef.current?.getCurrentTime() ?? 0;
    clientRef.current.sendSyncCommand({
      mediaId: videoId ?? room.mediaItem?.id ?? null,
      positionMs: pos * 1000,
      playing: nextPlaying,
    });
  }, [room.mediaItem?.id, videoId]);

  useEffect(() => {
    let active = true;
    clockRef.current.reset();
    syncRef.current = null;

    const client = new PlinkRealtimeClient({
      onStateChange: (c) => active && setConnected(c),
      onMessage: (msg) => active && setMessages((prev) => [...prev, msg]),
      onError: (e) => active && setError(e),
      onSessionReady: (msg) => {
        if (!active) return;
        if (msg.role === 'host' || msg.role === 'viewer') {
          setRole(msg.role);
          roleRef.current = msg.role;
        }
      },
      onClockProbeReply: (clientSentMs, serverMs) => {
        clockRef.current.ingest(clientSentMs, serverMs, Date.now());
      },
      onSyncState: (state: RoomState) => {
        if (!active) return;
        // Host ignores own echoes after first apply (viewers always apply)
        if (roleRef.current === 'host' && syncRef.current?.hasAppliedAnyState) {
          setDriftMs(syncRef.current.lastDriftMs);
          return;
        }
        const ctrl = ensureSync();
        ctrl.apply(state);
        setDriftMs(ctrl.lastDriftMs);
        setPlaying(state.playing);
        setPosition(state.positionMs / 1000);
      },
      onParticipantJoined: (uid, username) => {
        if (!active) return;
        setParticipants((prev) => {
          if (prev.some((p) => p.userId === uid)) return prev;
          return [...prev, { userId: uid, username }];
        });
      },
      onParticipantLeft: (uid) => {
        if (!active) return;
        setParticipants((prev) => prev.filter((p) => p.userId !== uid));
      },
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
  }, [room.id, room.code, ensureSync]);

  // Host: periodically publish position while playing
  useEffect(() => {
    if (!isHost || !isYouTube || !playerReady) return;
    const id = window.setInterval(() => {
      if (applyingRemote.current) return;
      if (ytRef.current?.isPlaying()) {
        pushHostState(true);
      }
    }, 2500);
    return () => window.clearInterval(id);
  }, [isHost, isYouTube, playerReady, pushHostState]);

  function sendMessage(e: FormEvent) {
    e.preventDefault();
    const text = draft.trim();
    if (!text) return;
    clientRef.current?.sendChat(text);
    analytics.messageSent();
    setDraft('');
  }

  useEffect(() => {
    if (Math.abs(driftMs) < 50) return;
    const t = window.setTimeout(() => analytics.syncDrift(Math.round(driftMs)), 2000);
    return () => window.clearTimeout(t);
  }, [driftMs]);

  function hostPlayPause() {
    if (!isHost) return;
    const next = !playing;
    if (next) ytRef.current?.play();
    else ytRef.current?.pause();
    setPlaying(next);
    pushHostState(next);
  }

  function hostSeek(delta: number) {
    if (!isHost) return;
    const cur = ytRef.current?.getCurrentTime() ?? position;
    const next = Math.max(0, cur + delta);
    ytRef.current?.seek(next);
    setPosition(next);
    pushHostState(playing, next);
  }

  const progressPct = duration > 0 ? Math.min(100, (position / duration) * 100) : 0;

  return (
    <div className="cinematic-room">
      <div className="player-stage">
        {isYouTube && videoId ? (
          <YouTubePlayer
            ref={ytRef}
            videoId={videoId}
            onReady={() => {
              setPlayerReady(true);
              ensureSync();
              // Host seeds initial paused/playing state
              if (isHost) {
                pushHostState(true, 0);
              } else {
                clientRef.current?.requestState();
              }
            }}
            onError={(code) => setError(`Player error ${code}`)}
            onTimeUpdate={(t, d, p) => {
              setPosition(t);
              setDuration(d);
              setPlaying(p);
            }}
          />
        ) : fallbackEmbed ? (
          <EmbedPlayer src={fallbackEmbed} title={room.name} />
        ) : (
          <div className="player-placeholder">No video selected</div>
        )}

        <div className="player-overlay">
          <div className="player-top-bar glass-pill">
            <button type="button" className="overlay-btn" onClick={onLeave} aria-label="Close">✕</button>
            <span className="overlay-title">{room.name}</span>
            <div className="overlay-top-actions">
              {onPopOut && (
                <button type="button" className="overlay-btn" onClick={onPopOut}>Pop out</button>
              )}
              <span className={`sync-pill ${connected ? 'live' : ''}`}>
                {connected ? (isHost ? 'Host · Synced' : 'Synced') : 'Connecting…'}
              </span>
              {connected && Math.abs(driftMs) > 50 && (
                <span className="sync-pill">{Math.round(driftMs)}ms</span>
              )}
            </div>
          </div>

          <div className="player-bottom glass-pill">
            <div className="player-meta">
              <strong>{room.mediaItem?.title ?? room.name}</strong>
              <span className="muted">
                Code {room.code} · {formatTime(position)} / {formatTime(duration)}
              </span>
            </div>
            <div className="player-progress">
              <div className="progress-track">
                <div className="progress-fill" style={{ width: `${progressPct}%` }} />
              </div>
            </div>
            <div className="player-pills">
              {isHost && isYouTube && (
                <>
                  <button type="button" className="meta-pill" onClick={() => hostSeek(-10)}>−10s</button>
                  <button type="button" className="meta-pill" onClick={hostPlayPause}>
                    {playing ? 'Pause' : 'Play'}
                  </button>
                  <button type="button" className="meta-pill" onClick={() => hostSeek(10)}>+10s</button>
                </>
              )}
              <button type="button" className="meta-pill" onClick={() => setChatOpen((o) => !o)}>
                Chat {messages.length > 0 && `(${messages.length})`}
              </button>
              <button type="button" className="meta-pill">
                Participants ({participants.length})
              </button>
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
