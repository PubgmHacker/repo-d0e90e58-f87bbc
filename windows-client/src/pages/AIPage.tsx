import { useState, type FormEvent } from 'react';
import { api } from '../lib/api';
import { analytics } from '../lib/analytics';
import { LivingBackdrop } from '../components/cinema/LivingBackdrop';
import { IconSparkles } from '../components/ui/Icons';

type Props = {
  onPickTrending: () => void;
};

type ChatLine = { role: 'user' | 'assistant'; text: string };

export function AIPage({ onPickTrending }: Props) {
  const [draft, setDraft] = useState('');
  const [lines, setLines] = useState<ChatLine[]>([
    {
      role: 'assistant',
      text: 'Привет! Я подскажу, что посмотреть вместе, или помогу создать комнату. Спроси что-нибудь.',
    },
  ]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  async function send(e?: FormEvent) {
    e?.preventDefault();
    const text = draft.trim();
    if (!text || loading) return;
    setDraft('');
    setError('');
    setLines((prev) => [...prev, { role: 'user', text }]);
    setLoading(true);
    try {
      const res = await api.aiChat(text);
      analytics.aiChat();
      const reply = res.message?.trim() || 'Не удалось получить ответ. Попробуй «Что посмотреть?» на главной.';
      setLines((prev) => [...prev, { role: 'assistant', text: reply }]);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'AI unavailable';
      setError(msg);
      setLines((prev) => [
        ...prev,
        {
          role: 'assistant',
          text: 'Сейчас ИИ недоступен. Открой тренды на главной и создай комнату вручную.',
        },
      ]);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="cinema-page ai-page">
      <LivingBackdrop animateThemes />
      <div className="ai-page-inner ai-chat-layout">
        <div className="ai-orb" aria-hidden>
          <div className="ai-orb-core" />
          <div className="ai-orb-ring" />
        </div>
        <h2>ИИ-помощник</h2>
        <p className="muted">Подскажет, что посмотреть с друзьями сегодня вечером</p>

        <div className="ai-chat-log glass-surface">
          {lines.map((line, i) => (
            <div key={i} className={`ai-chat-line ${line.role}`}>
              <span className="ai-chat-role">{line.role === 'user' ? 'Вы' : 'Plink AI'}</span>
              <p>{line.text}</p>
            </div>
          ))}
          {loading && <p className="muted ai-chat-loading">Думаю…</p>}
        </div>

        {error && <p className="error banner">{error}</p>}

        <form className="ai-chat-form" onSubmit={send}>
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Например: что посмотреть вечером?"
            disabled={loading}
          />
          <button type="submit" className="cinema-btn cinema-btn-accent" disabled={loading || !draft.trim()}>
            Отправить
          </button>
        </form>

        <button type="button" className="cinema-btn cinema-btn-wide" onClick={onPickTrending}>
          <IconSparkles size={16} />
          Открыть тренды
        </button>
      </div>
    </div>
  );
}
