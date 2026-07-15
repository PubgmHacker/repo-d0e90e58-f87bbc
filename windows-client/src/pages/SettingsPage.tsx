import { useState } from 'react';
import type { ChangeEvent } from 'react';
import { api, setToken } from '../lib/api';
import type { User } from '../lib/types';
import { LivingBackdrop } from '../components/cinema/LivingBackdrop';

// ════════════════════════════════════════════════════════════════════
// SettingsPage — Full settings with 6 sections (1:1 with iOS Profile)
// ════════════════════════════════════════════════════════════════════

type Props = {
  user: User;
  onUserUpdate: (user: User) => void;
  onLogout: () => void;
  onBack: () => void;
};

export function SettingsPage({ user, onUserUpdate, onLogout }: Props) {
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [showBlocked, setShowBlocked] = useState(false);

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
    <div className="cinema-page">
      <LivingBackdrop />
      <div className="cinema-page-inner" style={{ maxWidth: 720, margin: '0 auto' }}>
        {/* ═══ Profile Header ═══ */}
        <div className="profile-header" style={{ textAlign: 'center', marginBottom: 32, paddingTop: 40 }}>
          <label className="profile-avatar-wrap" title="Сменить аватар" style={{ cursor: 'pointer', display: 'inline-block', position: 'relative' }}>
            <div className="profile-ring" style={{
              position: 'absolute', inset: -4, borderRadius: '50%',
              background: 'linear-gradient(180deg, #2DE2E6 0%, #26D9A4 50%, #0EB5C9 100%)',
              animation: 'rotate 8s linear infinite',
            }} />
            <div className="profile-avatar" style={{
              position: 'relative', width: 80, height: 80, borderRadius: '50%',
              border: '4px solid #0E1113', background: 'linear-gradient(135deg, #2DE2E6 0%, #26D9A4 100%)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#0E1113', fontWeight: 700, fontSize: 32, overflow: 'hidden',
            }}>
              {user.avatarURL ? (
                <img src={user.avatarURL} alt={user.displayName} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <span>{initial}</span>
              )}
            </div>
            <input type="file" accept="image/*" hidden onChange={onAvatarPick} disabled={uploading} />
          </label>

          <h1 style={{ fontSize: 28, fontWeight: 800, color: '#ECEBEA', margin: '16px 0 4px', letterSpacing: -0.5 }}>
            {user.displayName || user.username}
          </h1>
          <p style={{ color: '#2DE2E6', fontSize: 15, margin: '0 0 4px' }}>@{user.username}</p>
          <p style={{ color: '#A6ACAD', fontSize: 13, margin: '0 0 16px' }}>{user.email}</p>

          <div style={{ display: 'flex', gap: 8, justifyContent: 'center' }}>
            {user.isPremium && (
              <span style={{ padding: '4px 12px', background: 'linear-gradient(135deg, #0EB5C9, #0E1113)', color: '#2DE2E6', borderRadius: 999, fontSize: 12, fontWeight: 700, border: '1px solid #2DE2E6' }}>✨ Plink+</span>
            )}
            {user.isAdmin && (
              <span style={{ padding: '4px 12px', background: 'rgba(209,75,69,0.15)', color: '#D14B45', borderRadius: 999, fontSize: 12, fontWeight: 700, border: '1px solid #D14B45' }}>👑 Админ</span>
            )}
          </div>

          {uploading && <p style={{ color: '#A6ACAD', fontSize: 13, marginTop: 8 }}>Загрузка аватара…</p>}
          {error && <p style={{ color: '#D14B45', fontSize: 13, marginTop: 8 }}>{error}</p>}
        </div>

        {/* ═══ Account Section ═══ */}
        <SettingsSection title="Аккаунт">
          <SettingsRow icon="👤" label="Имя пользователя" value={user.username} />
          <SettingsRow icon="📧" label="Email" value={user.email} />
          <SettingsRow icon="📷" label="Сменить аватар" onClick={() => (document.querySelector('input[type=file]') as HTMLInputElement | null)?.click()} />
        </SettingsSection>

        {/* ═══ Plink+ Section ═══ */}
        {!user.isPremium && (
          <SettingsSection title="Premium">
            <SettingsRow icon="✨" label="Получить Plink+" value="150₽/мес" onClick={() => window.open('/plink-plus', '_self')} />
            <SettingsRow icon="🎨" label="Живые темы" />
            <SettingsRow icon="😊" label="Кастомные emoji" />
            <SettingsRow icon="🎙" label="Voice chat" />
          </SettingsSection>
        )}

        {/* ═══ Settings Section ═══ */}
        <SettingsSection title="Настройки">
          <SettingsRow icon="🔔" label="Уведомления" onClick={() => alert('Скоро будет')} />
          <SettingsRow icon="🔒" label="Приватность" onClick={() => alert('Скоро будет')} />
          <SettingsRow icon="🚫" label="Заблокированные пользователи" onClick={() => setShowBlocked(true)} />
          <SettingsRow icon="🌐" label="Язык" value="Русский" />
          <SettingsRow icon="🎨" label="Тема оформления" value="Cinema2026" />
        </SettingsSection>

        {/* ═══ About Section ═══ */}
        <SettingsSection title="О приложении">
          <SettingsRow icon="ℹ️" label="Версия" value="1.0.0" />
          <SettingsRow icon="📜" label="Условия использования" onClick={() => window.open('/terms', '_self')} />
          <SettingsRow icon="🔐" label="Политика конфиденциальности" onClick={() => window.open('/privacy', '_self')} />
        </SettingsSection>

        {/* ═══ Logout Button ═══ */}
        <button
          type="button"
          onClick={logout}
          style={{
            width: '100%',
            padding: '14px',
            background: 'rgba(209,75,69,0.1)',
            border: '1px solid rgba(209,75,69,0.3)',
            borderRadius: 14,
            color: '#D14B45',
            fontSize: 16,
            fontWeight: 600,
            cursor: 'pointer',
            marginTop: 16,
            fontFamily: 'inherit',
            transition: 'all 0.15s',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = 'rgba(209,75,69,0.2)';
            e.currentTarget.style.borderColor = '#D14B45';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = 'rgba(209,75,69,0.1)';
            e.currentTarget.style.borderColor = 'rgba(209,75,69,0.3)';
          }}
        >
          Выйти
        </button>

        <div style={{ height: 40 }} />
      </div>

      {showBlocked && <BlockedUsersModal onClose={() => setShowBlocked(false)} />}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Settings Section (grouped card like iOS Settings)
// ════════════════════════════════════════════════════════════════════

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 24 }}>
      <h2 style={{
        fontSize: 13, fontWeight: 700, color: '#A6ACAD',
        textTransform: 'uppercase', letterSpacing: 0.5,
        margin: '0 0 8px 14px',
      }}>{title}</h2>
      <div style={{
        background: 'rgba(255,255,255,0.04)',
        backdropFilter: 'blur(20px)',
        border: '1px solid rgba(255,255,255,0.08)',
        borderRadius: 20,
        overflow: 'hidden',
      }}>
        {children}
      </div>
    </div>
  );
}

function SettingsRow({
  icon, label, value, onClick,
}: {
  icon: string; label: string; value?: string; onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={!onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 12,
        padding: '14px 16px', width: '100%',
        background: 'none', border: 'none',
        borderBottom: '1px solid rgba(255,255,255,0.08)',
        color: '#ECEBEA', fontSize: 16, textAlign: 'left',
        cursor: onClick ? 'pointer' : 'default',
        fontFamily: 'inherit',
        transition: 'background 0.15s',
      }}
      onMouseEnter={(e) => onClick && (e.currentTarget.style.background = 'rgba(255,255,255,0.04)')}
      onMouseLeave={(e) => (e.currentTarget.style.background = 'none')}
    >
      <span style={{ fontSize: 20, width: 24, textAlign: 'center' }}>{icon}</span>
      <span style={{ flex: 1 }}>{label}</span>
      {value && <span style={{ color: '#A6ACAD', fontSize: 14 }}>{value}</span>}
      {onClick && <span style={{ color: '#6E7578' }}>›</span>}
    </button>
  );
}

// ════════════════════════════════════════════════════════════════════
// Blocked Users Modal
// ════════════════════════════════════════════════════════════════════

function BlockedUsersModal({ onClose }: { onClose: () => void }) {
  const [blocked, setBlocked] = useState<Array<{ id: string; username: string }>>([]);
  const [loading, setLoading] = useState(true);

  useState(() => {
    api.moderationListBlocked?.()
      .then((res: any) => setBlocked(res?.blocked ?? []))
      .catch(() => setBlocked([]))
      .finally(() => setLoading(false));
  });

  return (
    <div className="modal-overlay" role="dialog" onClick={onClose}>
      <div className="modal auth-card" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 440, width: '90vw' }}>
        <h3 style={{ marginBottom: 16 }}>🚫 Заблокированные пользователи</h3>
        {loading ? (
          <p style={{ color: '#A6ACAD' }}>Загрузка...</p>
        ) : blocked.length === 0 ? (
          <p style={{ color: '#A6ACAD' }}>Список заблокированных пуст.</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {blocked.map((u) => (
              <div key={u.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 12, background: 'rgba(255,255,255,0.04)', borderRadius: 12 }}>
                <span style={{ flex: 1 }}>@{u.username}</span>
                <button
                  type="button"
                  onClick={async () => {
                    await api.moderationUnblock?.(u.id);
                    setBlocked(blocked.filter((b) => b.id !== u.id));
                  }}
                  style={{
                    padding: '6px 12px', borderRadius: 999,
                    background: 'rgba(45,226,230,0.1)', border: '1px solid rgba(45,226,230,0.3)',
                    color: '#2DE2E6', fontSize: 13, fontWeight: 600, cursor: 'pointer',
                  }}
                >
                  Разблокировать
                </button>
              </div>
            ))}
          </div>
        )}
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 16 }}>
          <button type="button" className="btn-secondary" style={{ height: 40, padding: '0 20px' }} onClick={onClose}>Закрыть</button>
        </div>
      </div>
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
