import type { ReactNode } from 'react';
import type { User } from '../../lib/types';
import {
  IconAi, IconChat, IconFriends, IconHome, IconPlus, IconRooms, IconSearch, IconSettings, IconUser,
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

const NAV: { id: NavItem; icon: ReactNode; label: string }[] = [
  { id: 'home', icon: <IconHome size={18} />, label: 'Home' },
  { id: 'search', icon: <IconSearch size={18} />, label: 'Search' },
  { id: 'rooms', icon: <IconRooms size={18} />, label: 'Rooms' },
  { id: 'friends', icon: <IconFriends size={18} />, label: 'Friends' },
  { id: 'dms', icon: <IconChat size={18} />, label: 'Messages' },
  { id: 'ai', icon: <IconAi size={18} />, label: 'AI Companion' },
  { id: 'settings', icon: <IconSettings size={18} />, label: 'Settings' },
];

export function DesktopShell({
  user, nav, collapsed, onNav, onToggleSidebar, detail, status, children, onNewRoom, onJoinCode,
}: Props) {
  return (
    <div className="desktop-app">
      <header className="titlebar">
        <span className="titlebar-brand">Plink</span>
        <div className="titlebar-actions">
          <button type="button" className="tb-btn primary" onClick={onNewRoom} title="New room (Ctrl+N)">
            <IconPlus size={14} />
            New Room
          </button>
          <button type="button" className="tb-btn" onClick={onJoinCode} title="Join (Ctrl+J)">
            Join
          </button>
        </div>
        <span className="titlebar-spacer" />
        <span className="titlebar-hint">⌘K search</span>
      </header>

      <div className="desktop-body">
        <aside className={`sidebar ${collapsed ? 'collapsed' : ''}`}>
          <button type="button" className="sidebar-toggle" onClick={onToggleSidebar} aria-label="Toggle sidebar">
            {collapsed ? '›' : '‹'}
          </button>
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
                {!collapsed && <span>{item.label}</span>}
              </button>
            ))}
          </nav>
          <div className="sidebar-footer">
            <button type="button" className="sidebar-user" onClick={() => onNav('profile')}>
              {user.avatarURL ? (
                <img src={user.avatarURL} alt="" className="sidebar-avatar" />
              ) : (
                <span className="sidebar-avatar">{user.username[0]?.toUpperCase()}</span>
              )}
              {!collapsed && (
                <span className="sidebar-user-meta">
                  <span className="sidebar-user-name">{user.username}</span>
                  <span className="sidebar-user-sub">{user.isPremium ? 'Plink+ member' : 'Free plan'}</span>
                </span>
              )}
              {collapsed && <IconUser size={16} />}
            </button>
            {user.isPremium && !collapsed && <span className="plink-plus-badge">Plink+</span>}
          </div>
        </aside>

        <main className="main-pane">{children}</main>

        {detail && <aside className="detail-pane">{detail}</aside>}
      </div>

      {status && <footer className="status-bar">{status}</footer>}
    </div>
  );
}