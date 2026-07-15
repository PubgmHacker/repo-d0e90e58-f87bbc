import type { ReactNode } from 'react';
import type { User } from '../../lib/types';
import { detectPlatform } from '../../lib/platform';
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

const NAV: { id: NavItem; icon: ReactNode; label: string }[] = [
  { id: 'home', icon: <IconHome size={18} />, label: 'Home' },
  { id: 'rooms', icon: <IconRooms size={18} />, label: 'Rooms' },
  { id: 'friends', icon: <IconFriends size={18} />, label: 'Friends' },
  { id: 'dms', icon: <IconChat size={18} />, label: 'Messages' },
  { id: 'ai', icon: <IconAi size={18} />, label: 'AI' },
  { id: 'settings', icon: <IconSettings size={18} />, label: 'Settings' },
];

export function DesktopShell({
  user, nav, collapsed, onNav, onToggleSidebar, detail, status, children, onNewRoom, onJoinCode,
}: Props) {
  const isMac = detectPlatform() === 'mac';

  return (
    <div className={`desktop-app ${isMac ? 'layout-mac' : 'layout-win'}`}>
      <header className="titlebar">
        <div className="titlebar-left">
          <span className="titlebar-brand">Plink</span>
          {!isMac && (
            <nav className="top-nav">
              {NAV.slice(0, 4).map((item) => (
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
          )}
        </div>

        <div className="titlebar-search">
          <IconSearch size={16} />
          <input type="search" placeholder="Search rooms, videos…" className="titlebar-search-input" />
        </div>

        <div className="titlebar-actions">
          <button type="button" className="tb-btn primary" onClick={onNewRoom} title="New room">
            <IconPlus size={14} />
            New Room
          </button>
          <button type="button" className="tb-btn" onClick={onJoinCode}>Join</button>
          <button type="button" className="titlebar-user" onClick={() => onNav('profile')}>
            {user.avatarURL ? (
              <img src={user.avatarURL} alt="" className="titlebar-avatar" />
            ) : (
              <span className="titlebar-avatar">{user.username[0]?.toUpperCase()}</span>
            )}
            <span className="titlebar-username">{user.username}</span>
          </button>
        </div>
      </header>

      <div className="desktop-body">
        {isMac && (
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
              {user.isPremium && !collapsed && <span className="plink-plus-badge">Plink+</span>}
            </div>
          </aside>
        )}

        <main className="main-pane">{children}</main>

        {detail && <aside className="detail-pane">{detail}</aside>}
      </div>

      {status && <footer className="status-bar"><span>{status}</span></footer>}
    </div>
  );
}