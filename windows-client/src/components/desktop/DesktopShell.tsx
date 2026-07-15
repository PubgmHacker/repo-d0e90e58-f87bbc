import type { ReactNode } from 'react';
import type { User } from '../../lib/types';
import {
  IconAi, IconChat, IconFriends, IconHome, IconPlus, IconRooms, IconSearch, IconSettings,
} from '../ui/Icons';

export type NavItem = 'home' | 'search' | 'rooms' | 'friends' | 'dms' | 'ai' | 'settings' | 'profile' | 'plus';

type Props = {
  user: User;
  nav: NavItem;
  collapsed: boolean;
  onNav: (item: NavItem) => void;
  onToggleSidebar: () => void;
  detail?: ReactNode;
  status?: string;
  children: ReactNode;
  onNewRoom?: () => void;
  onJoinCode?: () => void;
};

// iOS tab bar items — те же что в PlinkAppShell, но для desktop sidebar
const NAV: { id: NavItem; icon: ReactNode; label: string }[] = [
  { id: 'home', icon: <IconHome size={18} />, label: 'Главная' },
  { id: 'rooms', icon: <IconRooms size={18} />, label: 'Комнаты' },
  { id: 'friends', icon: <IconFriends size={18} />, label: 'Друзья' },
  { id: 'dms', icon: <IconChat size={18} />, label: 'Сообщения' },
  { id: 'ai', icon: <IconAi size={18} />, label: 'AI' },
  { id: 'settings', icon: <IconSettings size={18} />, label: 'Настройки' },
];

/**
 * Desktop Shell — 1:1 с iOS PlinkAppShell.
 * Единый дизайн для Mac и Windows.
 *
 * Layout:
 * ┌──────────────────────────────────────────────┐
 * │ Titlebar (drag region + brand + search)      │
 * ├─────────┬─────────────────────────────┬──────┤
 * │ Sidebar │ Main pane                   │Detail│
 * │ (220px) │ (flex)                      │(360) │
 * └─────────┴─────────────────────────────┴──────┘
 */
export function DesktopShell({
  user, nav, collapsed, onNav, onToggleSidebar, detail, status, children, onNewRoom, onJoinCode,
}: Props) {
  return (
    <div className="desktop-app">
      {/* Titlebar */}
      <header className="titlebar">
        <div className="titlebar-left">
          <span className="titlebar-brand">Plink</span>
          <button
            type="button"
            className="sidebar-toggle"
            onClick={onToggleSidebar}
            aria-label="Toggle sidebar"
            title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          >
            {collapsed ? '›' : '‹'}
          </button>
        </div>

        <div className="titlebar-search">
          <IconSearch size={16} />
          <input type="search" placeholder="Поиск комнат, видео…" className="titlebar-search-input" />
          <kbd className="kbd">⌘K</kbd>
        </div>

        <div className="titlebar-actions">
          <button type="button" className="tb-btn primary" onClick={onNewRoom} title="Новая комната (⌘N)">
            <IconPlus size={14} />
            <span>Новая комната</span>
          </button>
          <button type="button" className="tb-btn" onClick={onJoinCode} title="Присоединиться (⌘J)">
            Войти по коду
          </button>
          <button type="button" className="titlebar-user" onClick={() => onNav('profile')} title="Профиль">
            {user.avatarURL ? (
              <img src={user.avatarURL} alt="" className="titlebar-avatar" />
            ) : (
              <span className="titlebar-avatar placeholder">
                {user.username?.[0]?.toUpperCase() ?? '?'}
              </span>
            )}
            <span className="titlebar-username">{user.displayName || user.username}</span>
          </button>
        </div>
      </header>

      {/* Body */}
      <div className="desktop-body">
        {/* Sidebar — всегда видна, как iOS tab bar но вертикально */}
        <aside className={`sidebar ${collapsed ? 'collapsed' : ''}`}>
          <nav className="sidebar-nav">
            {NAV.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`sidebar-item ${nav === item.id ? 'active' : ''}`}
                onClick={() => onNav(item.id)}
                title={item.label}
              >
                <span className="sidebar-icon-wrap">{item.icon}</span>
                {!collapsed && <span className="sidebar-label">{item.label}</span>}
              </button>
            ))}
          </nav>

          <div className="sidebar-footer">
            {user.isPremium && !collapsed && (
              <div className="plink-plus-badge">
                <span className="plus-icon">✨</span>
                <span>Plink+</span>
              </div>
            )}
            {!user.isPremium && !collapsed && (
              <button
                type="button"
                className="sidebar-upgrade"
                onClick={() => onNav('plus')}
              >
                <span className="plus-icon">✨</span>
                <span>Получить Plink+</span>
              </button>
            )}
          </div>
        </aside>

        {/* Main content */}
        <main className="main-pane">{children}</main>

        {/* Optional detail pane (right) */}
        {detail && <aside className="detail-pane">{detail}</aside>}
      </div>

      {/* Status bar (как iOS status info) */}
      {status && (
        <footer className="status-bar">
          <span className="status-indicator" />
          <span>{status}</span>
        </footer>
      )}
    </div>
  );
}
