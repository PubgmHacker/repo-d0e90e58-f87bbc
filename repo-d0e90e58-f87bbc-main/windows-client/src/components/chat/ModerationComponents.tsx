import { useEffect, useRef, useState } from 'react';
import { api } from '../../lib/api';

// ════════════════════════════════════════════════════════════════════
// Moderation Components — Report + Block + Kick + Context Menu
// App Store / Web UGC compliance
// ════════════════════════════════════════════════════════════════════

interface ReportModalProps {
  userId: string;
  username: string;
  onClose: () => void;
  onSubmitted?: () => void;
}

export function ReportModal({ userId, username, onClose, onSubmitted }: ReportModalProps) {
  const [reason, setReason] = useState<'spam' | 'harassment' | 'nsfw' | 'other'>('spam');
  const [details, setDetails] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    setLoading(true);
    setError('');
    try {
      await api.moderationReport(userId, reason, details);
      onSubmitted?.();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to submit report');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="modal auth-card" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 440 }}>
        <h3 style={{ marginBottom: 16, color: 'var(--danger)' }}>🚩 Пожаловаться на @{username}</h3>

        <div style={{ marginBottom: 16 }}>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 8 }}>Причина:</p>
          {([
            ['spam', 'Спам'],
            ['harassment', 'Оскорбления'],
            ['nsfw', 'Неприемлемый контент'],
            ['other', 'Другое'],
          ] as const).map(([value, label]) => (
            <label key={value} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 0', cursor: 'pointer' }}>
              <input
                type="radio"
                checked={reason === value}
                onChange={() => setReason(value)}
                style={{ accentColor: 'var(--accent-bright)' }}
              />
              <span style={{ color: 'var(--text)' }}>{label}</span>
            </label>
          ))}
        </div>

        <textarea
          value={details}
          onChange={(e) => setDetails(e.target.value)}
          placeholder="Дополнительные детали (опционально)..."
          style={{
            width: '100%',
            minHeight: 80,
            padding: 12,
            background: 'var(--glass)',
            border: '1px solid var(--glass-border)',
            borderRadius: 12,
            color: 'var(--text)',
            fontSize: 14,
            resize: 'vertical',
            outline: 'none',
            fontFamily: 'inherit',
          }}
        />

        {error && <p className="auth-error" style={{ marginTop: 12 }}>{error}</p>}

        <div style={{ display: 'flex', gap: 8, marginTop: 16, justifyContent: 'flex-end' }}>
          <button
            type="button"
            className="btn-secondary"
            style={{ height: 40, padding: '0 20px', fontSize: 14 }}
            onClick={onClose}
          >
            Отмена
          </button>
          <button
            type="button"
            onClick={submit}
            disabled={loading}
            style={{
              height: 40,
              padding: '0 20px',
              fontSize: 14,
              border: 'none',
              borderRadius: 999,
              background: 'var(--danger)',
              color: 'white',
              fontWeight: 700,
              cursor: loading ? 'wait' : 'pointer',
              opacity: loading ? 0.6 : 1,
            }}
          >
            {loading ? 'Отправка...' : 'Отправить'}
          </button>
        </div>
      </div>
    </div>
  );
}

interface BlockModalProps {
  username: string;
  onClose: () => void;
  onConfirm: () => void;
}

export function BlockModal({ username, onClose, onConfirm }: BlockModalProps) {
  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="modal auth-card" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 400 }}>
        <h3 style={{ marginBottom: 12, color: 'var(--danger)' }}>🚫 Заблокировать @{username}?</h3>
        <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 20 }}>
          Их сообщения больше не будут видны. Разблокировать можно в Настройках.
        </p>
        <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
          <button
            type="button"
            className="btn-secondary"
            style={{ height: 40, padding: '0 20px', fontSize: 14 }}
            onClick={onClose}
          >
            Отмена
          </button>
          <button
            type="button"
            onClick={onConfirm}
            style={{
              height: 40,
              padding: '0 20px',
              fontSize: 14,
              border: 'none',
              borderRadius: 999,
              background: 'var(--danger)',
              color: 'white',
              fontWeight: 700,
              cursor: 'pointer',
            }}
          >
            Заблокировать
          </button>
        </div>
      </div>
    </div>
  );
}

interface KickModalProps {
  username: string;
  onClose: () => void;
  onConfirm: () => void;
}

export function KickModal({ username, onClose, onConfirm }: KickModalProps) {
  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="modal auth-card" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 400 }}>
        <h3 style={{ marginBottom: 12, color: 'var(--danger)' }}>👤 Выгнать @{username}?</h3>
        <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 20 }}>
          Пользователь будет удалён из комнаты. Не сможет вернуться без нового кода.
        </p>
        <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
          <button
            type="button"
            className="btn-secondary"
            style={{ height: 40, padding: '0 20px', fontSize: 14 }}
            onClick={onClose}
          >
            Отмена
          </button>
          <button
            type="button"
            onClick={onConfirm}
            style={{
              height: 40,
              padding: '0 20px',
              fontSize: 14,
              border: 'none',
              borderRadius: 999,
              background: 'var(--danger)',
              color: 'white',
              fontWeight: 700,
              cursor: 'pointer',
            }}
          >
            Выгнать
          </button>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Message Context Menu (right-click)
// ════════════════════════════════════════════════════════════════════

interface ContextMenuProps {
  x: number;
  y: number;
  isHost: boolean;
  onReport: () => void;
  onBlock: () => void;
  onKick: () => void;
  onClose: () => void;
}

export function MessageContextMenu({ x, y, isHost, onReport, onBlock, onKick, onClose }: ContextMenuProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        onClose();
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  const items = [
    { label: '🚩 Пожаловаться', color: 'var(--danger)', onClick: onReport },
    { label: '🚫 Заблокировать пользователя', color: 'var(--danger)', onClick: onBlock },
    ...(isHost ? [{ label: '👤 Выгнать из комнаты', color: 'var(--danger)', onClick: onKick }] : []),
  ];

  return (
    <div
      ref={ref}
      role="menu"
      style={{
        position: 'fixed',
        left: x,
        top: y,
        background: 'var(--glass-strong)',
        backdropFilter: 'blur(20px)',
        border: '1px solid var(--glass-border)',
        borderRadius: 14,
        padding: 6,
        zIndex: 1000,
        minWidth: 220,
        boxShadow: '0 12px 32px rgba(0,0,0,0.5)',
      }}
    >
      {items.map((item, i) => (
        <button
          key={i}
          role="menuitem"
          onClick={() => {
            item.onClick();
            onClose();
          }}
          style={{
            display: 'block',
            width: '100%',
            textAlign: 'left',
            padding: '8px 12px',
            background: 'none',
            border: 'none',
            borderRadius: 8,
            color: item.color,
            fontSize: 14,
            fontWeight: 500,
            cursor: 'pointer',
            fontFamily: 'inherit',
          }}
          onMouseEnter={(e) => (e.currentTarget.style.background = 'var(--glass)')}
          onMouseLeave={(e) => (e.currentTarget.style.background = 'none')}
        >
          {item.label}
        </button>
      ))}
    </div>
  );
}
