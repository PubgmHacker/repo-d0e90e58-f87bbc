import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, getToken, setToken } from './lib/api';
import type { Room, User } from './lib/types';
import { AuthPage } from './pages/AuthPage';
import { ProfilePage } from './pages/ProfilePage';
import { RoomPage } from './pages/RoomPage';
import { ProHomePage } from './pages/ProHomePage';
import { DesktopShell, type NavItem } from './components/desktop/DesktopShell';
import { DetailPane, type DetailTarget } from './components/desktop/DetailPane';
import { MiniPlayer } from './components/MiniPlayer';
import { useKeyboardShortcuts } from './hooks/useKeyboardShortcuts';
import { setupTrayListener } from './lib/tauri';
import { UrlDropZone } from './components/UrlDropZone';
import './App.css';

type Screen = 'auth' | 'app' | 'room' | 'profile';

export default function App() {
  const [screen, setScreen] = useState<Screen>('auth');
  const [user, setUser] = useState<User | null>(null);
  const [room, setRoom] = useState<Room | null>(null);
  const [booting, setBooting] = useState(true);
  const [nav, setNav] = useState<NavItem>('home');
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [detail, setDetail] = useState<DetailTarget>(null);
  const [joinPrompt, setJoinPrompt] = useState(false);
  const [miniPlayer, setMiniPlayer] = useState<{ title: string; url: string } | null>(null);
  const [status, setStatus] = useState('Ready');

  useEffect(() => {
    (async () => {
      if (!getToken()) { setBooting(false); return; }
      try {
        const me = await api.getMe();
        setUser(me);
        setScreen('app');
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
  }, []);

  const handlers = useMemo(() => ({
    onSearch: () => document.querySelector<HTMLInputElement>('.pro-search')?.focus(),
    onNewRoom: () => setNav('home'),
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

  if (booting) return <div className="page center">Plink Desktop…</div>;

  if (screen === 'auth' || !user) {
    return (
      <AuthPage
        onAuth={(u) => {
          setUser(u);
          setScreen('app');
        }}
      />
    );
  }

  if (screen === 'profile' || nav === 'profile') {
    return (
      <DesktopShell
        user={user}
        nav="profile"
        collapsed={sidebarCollapsed}
        onNav={(n) => { if (n === 'home') setScreen('app'); else setNav(n); }}
        onToggleSidebar={() => setSidebarCollapsed((c) => !c)}
        status={status}
      >
        <ProfilePage
          user={user}
          onUserUpdate={setUser}
          onLogout={() => { setUser(null); setScreen('auth'); }}
          onBack={() => { setNav('home'); setScreen('app'); }}
        />
      </DesktopShell>
    );
  }

  if (screen === 'room' && room) {
    const embed = room.mediaItem?.videoId
      ? `https://www.youtube.com/embed/${room.mediaItem.videoId}?autoplay=1`
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

  return (
    <UrlDropZone onUrl={() => setJoinPrompt(true)}>
      <DesktopShell
        user={user}
        nav={nav}
        collapsed={sidebarCollapsed}
        onNav={(n) => { if (n === 'profile') setScreen('profile'); else setNav(n); }}
        onToggleSidebar={() => setSidebarCollapsed((c) => !c)}
        detail={<DetailPane target={detail} onJoinRoom={openRoom} />}
        status={status}
        onNewRoom={() => setNav('home')}
        onJoinCode={() => setJoinPrompt(true)}
      >
        <ProHomePage
          onOpenRoom={openRoom}
          onHoverChange={setDetail}
          onJoinPrompt={() => setJoinPrompt(true)}
        />
      </DesktopShell>

      {joinPrompt && (
        <div className="modal-overlay" role="dialog">
          <div className="modal glass-panel">
            <h3>Join by code</h3>
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

  async function submit() {
    try {
      const room = await api.joinRoom(code.trim().toUpperCase());
      onJoined(room);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Join failed');
    }
  }

  return (
    <>
      <input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="ABCD12" />
      {err && <p className="error">{err}</p>}
      <div className="modal-actions">
        <button type="button" onClick={onClose}>Cancel</button>
        <button type="button" className="pro-btn primary" onClick={submit}>Join</button>
      </div>
    </>
  );
}