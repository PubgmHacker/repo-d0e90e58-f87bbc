import { useState } from 'react';
import type { FormEvent } from 'react';
import { api, setToken } from '../lib/api';
import type { User } from '../lib/types';
import { PosterMosaic } from '../components/auth/PosterMosaic';

type Props = {
  onAuth: (user: User, token: string) => void;
};

/**
 * AuthPage — 1:1 with iOS CinematicAuthContainer.
 * Layout: PosterMosaic (left) + auth card (right, glassmorphism).
 */
export function AuthPage({ onAuth }: Props) {
  const [mode, setMode] = useState<'signin' | 'signup'>('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const res = mode === 'signin'
        ? await api.signIn(email, password)
        : await api.signUp(email, password, username);
      setToken(res.token);
      onAuth(res.user, res.token);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка авторизации');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-page">
      <PosterMosaic />
      <div className="auth-form-panel">
        <div className="auth-card">
          <div style={{ textAlign: 'center', marginBottom: 32 }}>
            <h1 style={{
              fontSize: 40,
              fontWeight: 800,
              letterSpacing: '-0.03em',
              margin: 0,
              background: 'var(--gradient-bio)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              backgroundClip: 'text',
            }}>
            Plink
            </h1>
            <p style={{
              margin: '4px 0 0',
              color: 'var(--text-secondary)',
              fontSize: 14,
            }}>
              Смотрите вместе. Где угодно. Вместе.
            </p>
          </div>

          <h1 style={{ fontSize: 28, fontWeight: 700, margin: '0 0 8px' }}>
            {mode === 'signin' ? 'С возвращением' : 'Создать аккаунт'}
          </h1>
          <p className="auth-sub">
            {mode === 'signin'
              ? 'Войдите, чтобы продолжить'
              : 'Присоединяйся к Plink — синхронный просмотр с друзьями'}
          </p>

          <form onSubmit={handleSubmit}>
            {mode === 'signup' && (
              <>
                <label htmlFor="username">ИМЯ ПОЛЬЗОВАТЕЛЯ</label>
                <input
                  id="username"
                  placeholder="yourname"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                  minLength={5}
                  maxLength={32}
                  autoComplete="username"
                />
              </>
            )}
            <label htmlFor="email">EMAIL</label>
            <input
              id="email"
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
            />
            <label htmlFor="password">ПАРОЛЬ</label>
            <input
              id="password"
              type="password"
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={6}
              autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
            />
            {error && <p className="error banner">{error}</p>}
            <button type="submit" className="submit-btn" disabled={loading}>
              {loading ? 'Подождите…' : mode === 'signin' ? 'Войти' : 'Создать аккаунт'}
            </button>
          </form>

          <div className="auth-switch">
            {mode === 'signin' ? 'Нет аккаунта?' : 'Уже есть аккаунт?'}
            <button type="button" onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}>
              {mode === 'signin' ? 'Создать' : 'Войти'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
