import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, getToken, setToken, youtubeMediaItem } from './lib/api';
import { analytics } from './lib/analytics';
import type { Room, User } from './lib/types';
import { AuthPage } from './pages/AuthPage';
import { RoomPage } from './pages/RoomPage';
import { ProHomePage } from './pages/ProHomePage';
import { RoomsPage } from './pages/RoomsPage';
import { AIPage } from './pages/AIPage';
import { FriendsPage } from './pages/FriendsPage';
import { SettingsPage } from './pages/SettingsPage';
import { DMPage } from './pages/DMPage';
import { DesktopShell, type NavItem } from './components/desktop/DesktopShell';
import { MiniPlayer } from './components/MiniPlayer';
import { useKeyboardShortcuts } from './hooks/useKeyboardShortcuts';
import { setupTrayListener } from './lib/tauri';
import { UrlDropZone } from './components/UrlDropZone';
import './App.css';

type Screen = 'auth' | 'app' | 'room';

export default function App() {
  const [screen, setScreen] = useState<Screen>('auth');
  const [user, setUser] = useState<User | null>(null);
  const [room, setRoom] = useState<Room | null>(null);
  const [booting, setBooting] = useState(true);
  const [nav, setNav] = useState<NavItem>('home');
  const [joinPrompt, setJoinPrompt] = useState(false);
  const [miniPlayer, setMiniPlayer] = useState<{ title: string; url: string } | null>(null);
  const [status, setStatus] = useState('Ready');

  useEffect(() => {
    analytics.appOpen();
    (async () => {
      if (!getToken()) { setBooting(false); return; }
      try {
        const me = await api.getMe();
        setUser(me);
        setScreen('app');
        analytics.login();
      } catch {
        setToken(null);
      } finally {
        setBooting(false);
      }
    })();
  }, []);

  const openRoom = useCallback((r: Room) => {
    setRoom(r);
    setScreen('room');
    setStatus(`Now Playing: ${r.name}`);
    analytics.roomJoined();
  }, []);

  const quickCreateRoom = useCallback(async () => {
    try {
      const t = await api.getTrending();
      const video = t.results?.[0];
      if (!video) {
        setJoinPrompt(true);
        return;
      }
      const created = await api.createRoom(
        video.title,
        youtubeMediaItem(video.id, video.title, video.thumbnailURL),
      );
      analytics.roomCreated();
      openRoom(await api.joinRoom(created.code));
    } catch {
      setJoinPrompt(true);
    }
  }, [openRoom]);

  const handleNav = useCallback((item: NavItem) => {
    setNav(item);
    setScreen('app');
  }, []);

  const handlers = useMemo(() => ({
    onSearch: () => document.querySelector<HTMLInputElement>('.pro-search')?.focus(),
    onNewRoom: () => { setNav('home'); setScreen('app'); },
    onJoin: () => setJoinPrompt(true),
    onEscape: () => { setMiniPlayer(null); if (screen === 'room') { setRoom(null); setScreen('app'); } },
  }), [screen]);

  useKeyboardShortcuts(handlers, screen !== 'auth');

  useEffect(() => {
    let cleanup: (() => void) | undefined;
    setupTrayListener((action) => {
      if (action === 'new_room') {
        setScreen('app');
        setNav('home');
      }
      if (action === 'join') setJoinPrompt(true);
    }).then((unlisten) => {
      cleanup = () => { unlisten(); };
    });
    return () => cleanup?.();
  }, []);

  if (booting) return <div className="page center">Loading Plink…</div>;

  if (screen === 'auth' || !user) {
    return (
      <AuthPage
        onAuth={(u) => {
          setUser(u);
          setScreen('app');
          setNav('home');
          analytics.login();
        }}
      />
    );
  }

  if (screen === 'room' && room) {
    const embed = room.mediaItem?.videoId
      ? `https://plink-backend-production-ef31.up.railway.app/api/media/youtube-player?id=${room.mediaItem.videoId}`
      : room.mediaItem?.streamURL ?? '';

    return (
      <>
        <RoomPage
          room={room}
          userId={user.id}
          onLeave={() => { setRoom(null); setScreen('app'); setStatus('Ready'); }}
          onPopOut={() => embed && setMiniPlayer({ title: room.name, url: embed })}
        />
        {miniPlayer && (
          <MiniPlayer
            title={miniPlayer.title}
            embedUrl={miniPlayer.url}
            onClose={() => setMiniPlayer(null)}
            onExpand={() => setMiniPlayer(null)}
          />
        )}
      </>
    );
  }

  const currentUser = user;

  function renderTab() {
    switch (nav) {
      case 'home':
        return (
          <ProHomePage
            onOpenRoom={openRoom}
            onJoinPrompt={() => setJoinPrompt(true)}
            onOpenAI={() => setNav('ai')}
          />
        );
      case 'rooms':
        return <RoomsPage onOpenRoom={openRoom} onCreate={quickCreateRoom} />;
      case 'ai':
        return <AIPage onPickTrending={() => setNav('home')} />;
      case 'friends':
        return <FriendsPage />;
      case 'dms':
        return <DMPage />;
      case 'settings':
        return (
          <SettingsPage
            user={currentUser!}
            onUserUpdate={setUser}
            onLogout={() => { setUser(null); setScreen('auth'); setNav('home'); }}
            onBack={() => setNav('home')}
          />
        );
      default:
        return null;
    }
  }

  return (
    <UrlDropZone onUrl={() => setJoinPrompt(true)}>
      <DesktopShell user={user} nav={nav} onNav={handleNav} status={status}>
        {renderTab()}
      </DesktopShell>

      {joinPrompt && (
        <div className="modal-overlay" role="dialog" onClick={() => setJoinPrompt(false)}>
          <div className="modal glass-panel" onClick={(e) => e.stopPropagation()}>
            <h3>Войти по коду</h3>
            <JoinByCodeForm
              onClose={() => setJoinPrompt(false)}
              onJoined={(r) => { setJoinPrompt(false); openRoom(r); }}
            />
          </div>
        </div>
      )}
    </UrlDropZone>
  );
}

function JoinByCodeForm({ onClose, onJoined }: { onClose: () => void; onJoined: (r: Room) => void }) {
  const [code, setCode] = useState('');
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(false);

  async function submit() {
    if (!code.trim()) return;
    setLoading(true);
    setErr('');
    try {
      const joined = await api.joinRoom(code.trim().toUpperCase());
      onJoined(joined);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Join failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <input
        value={code}
        onChange={(e) => setCode(e.target.value.toUpperCase())}
        placeholder="ABCD12"
        autoFocus
        onKeyDown={(e) => e.key === 'Enter' && submit()}
      />
      {err && <p className="error">{err}</p>}
      <div className="modal-actions">
        <button type="button" onClick={onClose}>Отмена</button>
        <button type="button" className="pro-btn primary" onClick={submit} disabled={loading}>
          {loading ? 'Вход…' : 'Войти'}
        </button>
      </div>
    </>
  );
}