import { useEffect, useState } from 'react';
import { LivingBackdrop } from '../components/cinema/LivingBackdrop';

// ════════════════════════════════════════════════════════════════════
// DMPage — Direct messages list + chat view
// ════════════════════════════════════════════════════════════════════

interface DMDialog {
  id: string;
  friendId: string;
  friendName: string;
  friendAvatar?: string;
  lastMessage: string;
  lastMessageAt: string;
  unreadCount: number;
}

interface DMMessage {
  id: string;
  senderId: string;
  text: string;
  createdAt: string;
}

export function DMPage() {
  const [dialogs, setDialogs] = useState<DMDialog[]>([]);
  const [selectedDialog, setSelectedDialog] = useState<DMDialog | null>(null);
  const [messages, setMessages] = useState<DMMessage[]>([]);
  const [draft, setDraft] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // TODO: replace with real API when DM endpoint exists
    // For now, simulate empty state
    setTimeout(() => {
      setDialogs([]);
      setLoading(false);
    }, 500);
  }, []);

  async function sendMessage() {
    if (!draft.trim() || !selectedDialog) return;
    const newMsg: DMMessage = {
      id: Date.now().toString(),
      senderId: 'me',
      text: draft,
      createdAt: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, newMsg]);
    setDraft('');
    // TODO: api.sendDM(selectedDialog.friendId, draft)
  }

  if (loading) {
    return (
      <div className="cinema-page">
        <LivingBackdrop />
        <div className="cinema-page-inner">
          <p style={{ color: '#A6ACAD' }}>Загрузка сообщений...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="cinema-page">
      <LivingBackdrop />
      <div className="cinema-page-inner">
        <header className="cinema-page-head">
          <h2>Сообщения</h2>
        </header>

        {dialogs.length === 0 && !selectedDialog ? (
          <div className="cinema-empty glass-surface" style={{
            padding: 48, textAlign: 'center', marginTop: 32,
          }}>
            <div style={{ fontSize: 48, marginBottom: 16 }}>💬</div>
            <h3 style={{ color: 'var(--text)', margin: '0 0 8px', fontSize: 18, fontWeight: 700 }}>Нет сообщений</h3>
            <p style={{ color: 'var(--text-secondary)', margin: '0 0 16px', fontSize: 14 }}>
              Начни диалог с другом из раздела Друзья
            </p>
            <button
              type="button"
              className="cinema-btn cinema-btn-light"
              onClick={() => window.location.hash = '#friends'}
            >
              Перейти к друзьям
            </button>
          </div>
        ) : selectedDialog ? (
          // Chat view
          <div style={{ display: 'flex', flexDirection: 'column', height: '70vh' }}>
            <header style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '12px 16px', borderBottom: '1px solid rgba(255,255,255,0.08)',
            }}>
              <button
                type="button"
                onClick={() => setSelectedDialog(null)}
                style={{ background: 'none', border: 'none', color: '#2DE2E6', cursor: 'pointer', fontSize: 18 }}
              >
                ← Назад
              </button>
              <div style={{
                width: 36, height: 36, borderRadius: '50%',
                background: 'linear-gradient(135deg, #2DE2E6, #26D9A4)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: '#0E1113', fontWeight: 700,
              }}>
                {selectedDialog.friendName[0]?.toUpperCase()}
              </div>
              <strong>{selectedDialog.friendName}</strong>
            </header>

            <div style={{ flex: 1, overflowY: 'auto', padding: 16, display: 'flex', flexDirection: 'column', gap: 8 }}>
              {messages.length === 0 ? (
                <p style={{ color: '#6E7578', textAlign: 'center', marginTop: 'auto', marginBottom: 'auto' }}>
                  Нет сообщений. Напиши первым!
                </p>
              ) : (
                messages.map((m) => (
                  <div
                    key={m.id}
                    style={{
                      alignSelf: m.senderId === 'me' ? 'flex-end' : 'flex-start',
                      maxWidth: '70%',
                      padding: '10px 14px',
                      borderRadius: 18,
                      background: m.senderId === 'me'
                        ? 'linear-gradient(135deg, #2DE2E6, #26D9A4)'
                        : 'rgba(255,255,255,0.04)',
                      color: m.senderId === 'me' ? '#0E1113' : '#ECEBEA',
                      fontSize: 14,
                      fontWeight: m.senderId === 'me' ? 500 : 'normal',
                    }}
                  >
                    {m.text}
                  </div>
                ))
              )}
            </div>

            <form
              onSubmit={(e) => { e.preventDefault(); sendMessage(); }}
              style={{ display: 'flex', gap: 8, padding: 12, borderTop: '1px solid rgba(255,255,255,0.08)' }}
            >
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                placeholder="Сообщение..."
                style={{
                  flex: 1, padding: '10px 16px',
                  background: 'rgba(255,255,255,0.04)',
                  border: '1px solid rgba(255,255,255,0.08)',
                  borderRadius: 999,
                  color: '#ECEBEA', fontSize: 14, outline: 'none',
                  fontFamily: 'inherit',
                }}
              />
              <button
                type="submit"
                disabled={!draft.trim()}
                style={{
                  width: 36, height: 36, borderRadius: '50%',
                  background: 'linear-gradient(135deg, #2DE2E6, #26D9A4)',
                  border: 'none', color: '#0E1113',
                  fontWeight: 700, cursor: 'pointer',
                  opacity: draft.trim() ? 1 : 0.4,
                }}
              >
                ➤
              </button>
            </form>
          </div>
        ) : (
          // Dialog list
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {dialogs.map((d) => (
              <button
                key={d.id}
                type="button"
                onClick={() => setSelectedDialog(d)}
                style={{
                  display: 'flex', alignItems: 'center', gap: 12,
                  padding: 14, background: 'rgba(255,255,255,0.04)',
                  border: '1px solid rgba(255,255,255,0.08)',
                  borderRadius: 14, cursor: 'pointer', textAlign: 'left',
                  fontFamily: 'inherit',
                }}
              >
                <div style={{
                  width: 44, height: 44, borderRadius: '50%',
                  background: 'linear-gradient(135deg, #2DE2E6, #26D9A4)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  color: '#0E1113', fontWeight: 700,
                }}>
                  {d.friendName[0]?.toUpperCase()}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <strong style={{ color: '#ECEBEA' }}>{d.friendName}</strong>
                  <p style={{ color: '#A6ACAD', fontSize: 13, margin: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {d.lastMessage}
                  </p>
                </div>
                {d.unreadCount > 0 && (
                  <span style={{
                    background: '#2DE2E6', color: '#0E1113',
                    borderRadius: 999, padding: '2px 8px',
                    fontSize: 12, fontWeight: 700,
                  }}>
                    {d.unreadCount}
                  </span>
                )}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
