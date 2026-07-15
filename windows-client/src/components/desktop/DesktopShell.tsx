import type { ReactNode } from 'react';
import type { User } from '../../lib/types';

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

const NAV: { id: NavItem; icon: string; label: string }[] = [
  { id: 'home', icon: '🏠', label: 'Home' },
  { id: 'search', icon: '🔍', label: 'Search' },
  { id: 'rooms', icon: '📺', label: 'Rooms' },
  { id: 'friends', icon: '👥', label: 'Friends' },
  { id: 'dms', icon: '💬', label: 'DMs' },
  { id: 'ai', icon: '🤖', label: 'AI' },
  { id: 'settings', icon: '⚙', label: 'Settings' },
];

export function DesktopShell({
  user, nav, collapsed, onNav, onToggleSidebar, detail, status, children, onNewRoom, onJoinCode,
}: Props) {
  return (
    <div className="desktop-app">
      <header className="titlebar">
        <span className="titlebar-brand">Plink</span>
        <div className="titlebar-actions">
          <button type="button" onClick={onNewRoom} title="New room (Ctrl+N)">+ Room</button>
          <button type="button" onClick={onJoinCode} title="Join (Ctrl+J)">Join</button>
        </div>
        <span className="titlebar-spacer" />
        <span className="titlebar-hint">Ctrl+K search</span>
      </header>

      <div className="desktop-body">
        <aside className={`sidebar ${collapsed ? 'collapsed' : ''}`}>
          <button type="button" className="sidebar-toggle" onClick={onToggleSidebar} aria-label="Toggle sidebar">
            {collapsed ? '»' : '«'}
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
                <span className="sidebar-icon">{item.icon}</span>
                {!collapsed && <span>{item.label}</span>}
              </button>
            ))}
          </nav>
          <div className="sidebar-footer">
            <button type="button" className="sidebar-item" onClick={() => onNav('profile')}>
              <span className="sidebar-icon">👤</span>
              {!collapsed && <span>{user.username}</span>}
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