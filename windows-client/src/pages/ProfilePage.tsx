import { useState } from 'react';
import type { ChangeEvent } from 'react';
import { api, setToken } from '../lib/api';
import type { User } from '../lib/types';

type Props = {
  user: User;
  onUserUpdate: (user: User) => void;
  onLogout: () => void;
  onBack: () => void;
};

/**
 * ProfilePage — 1:1 with iOS ProfileView.
 * Sections:
 * 1. Avatar (80pt + rotating gradient ring)
 * 2. Name, @username, email
 * 3. Badges (Plink+, Admin)
 * 4. Grouped cards (Account, Notifications, etc — как iOS Settings)
 * 5. Logout button (red, как iOS)
 */
export function ProfilePage({ user, onUserUpdate, onLogout }: Props) {
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);

  async function onAvatarPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setError('');
    try {
      const dataUrl = await fileToDataUrl(file);
      const res = await api.uploadAvatar(dataUrl);
      onUserUpdate({ ...user, avatarURL: res.avatarURL, avatarData: res.avatarData });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
    }
  }

  function logout() {
    setToken(null);
    onLogout();
  }

  const initial = user.displayName?.[0]?.toUpperCase() ?? user.username?.[0]?.toUpperCase() ?? '?';

  return (
    <div className="profile-page">
      {/* Avatar + name section */}
      <div className="profile-header">
        <label className="profile-avatar-wrap" title="Сменить аватар">
          <div className="profile-ring" />
          <div className="profile-avatar">
            {user.avatarURL ? (
              <img src={user.avatarURL} alt={user.displayName} style={{ width: '100%', height: '100%', borderRadius: '50%', objectFit: 'cover' }} />
            ) : (
              <span>{initial}</span>
            )}
          </div>
          <input type="file" accept="image/*" hidden onChange={onAvatarPick} disabled={uploading} />
        </label>

        <h1 className="profile-name">{user.displayName || user.username}</h1>
        <p className="profile-username">@{user.username}</p>
        <p className="profile-email">{user.email}</p>

        <div className="profile-badges">
          {user.isPremium && <span className="badge badge-premium">✨ Plink+</span>}
          {user.isAdmin && <span className="badge badge-admin">👑 Админ</span>}
        </div>

        {uploading && <p style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Загрузка аватара…</p>}
        {error && <p className="error">{error}</p>}
      </div>

      {/* Account section */}
      <div className="profile-section">
        <h2 className="profile-section-title">Аккаунт</h2>
        <div className="profile-card">
          <button type="button" className="profile-row">
            <span className="profile-row-icon">👤</span>
            <span className="profile-row-label">Имя пользователя</span>
            <span className="profile-row-value">{user.username}</span>
            <span className="profile-row-chevron">›</span>
          </button>
          <button type="button" className="profile-row">
            <span className="profile-row-icon">📧</span>
            <span className="profile-row-label">Email</span>
            <span className="profile-row-value">{user.email}</span>
            <span className="profile-row-chevron">›</span>
          </button>
          <label className="profile-row" style={{ cursor: 'pointer' }}>
            <span className="profile-row-icon">📷</span>
            <span className="profile-row-label">Сменить аватар</span>
            <span className="profile-row-chevron">›</span>
            <input type="file" accept="image/*" hidden onChange={onAvatarPick} disabled={uploading} />
          </label>
        </div>
      </div>

      {/* Plink+ section */}
      {!user.isPremium && (
        <div className="profile-section">
          <h2 className="profile-section-title">Premium</h2>
          <div className="profile-card">
            <button type="button" className="profile-row">
              <span className="profile-row-icon">✨</span>
              <span className="profile-row-label">Получить Plink+</span>
              <span className="profile-row-value">150₽/мес</span>
              <span className="profile-row-chevron">›</span>
            </button>
            <button type="button" className="profile-row">
              <span className="profile-row-icon">🎨</span>
              <span className="profile-row-label">Живые темы</span>
              <span className="profile-row-chevron">›</span>
            </button>
            <button type="button" className="profile-row">
              <span className="profile-row-icon">😊</span>
              <span className="profile-row-label">Кастомные emoji</span>
              <span className="profile-row-chevron">›</span>
            </button>
            <button type="button" className="profile-row">
              <span className="profile-row-icon">🎙</span>
              <span className="profile-row-label">Voice chat</span>
              <span className="profile-row-chevron">›</span>
            </button>
          </div>
        </div>
      )}

      {/* Settings section */}
      <div className="profile-section">
        <h2 className="profile-section-title">Настройки</h2>
        <div className="profile-card">
          <button type="button" className="profile-row">
            <span className="profile-row-icon">🔔</span>
            <span className="profile-row-label">Уведомления</span>
            <span className="profile-row-chevron">›</span>
          </button>
          <button type="button" className="profile-row">
            <span className="profile-row-icon">🔒</span>
            <span className="profile-row-label">Приватность</span>
            <span className="profile-row-chevron">›</span>
          </button>
          <button type="button" className="profile-row">
            <span className="profile-row-icon">🌐</span>
            <span className="profile-row-label">Язык</span>
            <span className="profile-row-value">Русский</span>
            <span className="profile-row-chevron">›</span>
          </button>
          <button type="button" className="profile-row">
            <span className="profile-row-icon">🎨</span>
            <span className="profile-row-label">Тема оформления</span>
            <span className="profile-row-value">Cinema2026</span>
            <span className="profile-row-chevron">›</span>
          </button>
        </div>
      </div>

      {/* About section */}
      <div className="profile-section">
        <h2 className="profile-section-title">О приложении</h2>
        <div className="profile-card">
          <button type="button" className="profile-row">
            <span className="profile-row-icon">ℹ️</span>
            <span className="profile-row-label">Версия</span>
            <span className="profile-row-value">1.0.0</span>
          </button>
          <button type="button" className="profile-row">
            <span className="profile-row-icon">📜</span>
            <span className="profile-row-label">Условия использования</span>
            <span className="profile-row-chevron">›</span>
          </button>
          <button type="button" className="profile-row">
            <span className="profile-row-icon">🔐</span>
            <span className="profile-row-label">Политика конфиденциальности</span>
            <span className="profile-row-chevron">›</span>
          </button>
        </div>
      </div>

      {/* Logout (red, как iOS destructive button) */}
      <button type="button" className="btn-logout" onClick={logout}>
        Выйти
      </button>
    </div>
  );
}

function fileToDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error('Failed to read file'));
    reader.readAsDataURL(file);
  });
}
