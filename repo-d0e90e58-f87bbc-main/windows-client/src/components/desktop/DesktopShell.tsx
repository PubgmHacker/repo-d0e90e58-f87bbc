import type { ReactNode } from 'react';
import type { User } from '../../lib/types';

export type NavItem = 'home' | 'rooms' | 'ai' | 'friends' | 'dms' | 'settings';

type Props = {
  user: User;
  nav: NavItem;
  onNav: (item: NavItem) => void;
  children: ReactNode;
  status?: string;
};

const TOP_NAV: { id: NavItem; label: string }[] = [
  { id: 'home', label: 'Главная' },
  { id: 'rooms', label: 'Комнаты' },
  { id: 'ai', label: 'ИИ' },
  { id: 'friends', label: 'Друзья' },
  { id: 'dms', label: 'Сообщения' },
  { id: 'settings', label: 'Настройки' },
];

export function DesktopShell({ user, nav, onNav, status, children }: Props) {
  return (
    <div className="desktop-app">
      <header className="app-header">
        <nav className="top-nav">
          {TOP_NAV.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`top-nav-item ${nav === item.id ? 'active' : ''}`}
              onClick={() => onNav(item.id)}
            >
              {item.label}
            </button>
          ))}
        </nav>

        <button type="button" className="header-avatar-btn" onClick={() => onNav('settings')} aria-label="Настройки">
          {user.avatarURL ? (
            <img src={user.avatarURL} alt="" className="header-avatar" />
          ) : (
            <span className="header-avatar">{user.username[0]?.toUpperCase()}</span>
          )}
        </button>
      </header>

      <main className="main-pane">{children}</main>

      {status && <footer className="status-bar"><span>{status}</span></footer>}
    </div>
  );
}