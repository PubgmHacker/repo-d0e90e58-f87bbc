import { useState } from 'react';
import type { FormEvent } from 'react';
import { api, setToken } from '../lib/api';
import type { User } from '../lib/types';

type Props = {
  onAuth: (user: User, token: string) => void;
};

/**
 * AuthPage — 1:1 с iOS CinematicAuthContainer.
 * Композиция:
 *  - Plink gradient logo
 *  - "Смотрим вместе" + EN подзаголовок
 *  - 5 постеров аркой (cyan-glowing border)
 *  - Силуэт на светящейся платформе
 *  - Glass card с Username/Email/Password
 *  - "Регистрация" (gradient) + "Вход" (glass border)
 *  - 4 плавающих orbs на обсидиан фоне
 */
export function AuthPage({ onAuth }: Props) {
  const [isSignUp, setSignUp] = useState(true);
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
      const res = isSignUp
        ? await api.signUp(email, password, username)
        : await api.signIn(email, password);
      setToken(res.token);
      onAuth(res.user, res.token);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка авторизации');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="cinematic-auth">
      {/* ═══ BACKGROUND: obsidian + 4 floating orbs ═══ */}
      <div className="auth-bg">
        <div className="orb orb-1" />
        <div className="orb orb-2" />
        <div className="orb orb-3" />
        <div className="orb orb-4" />
      </div>

      {/* ═══ CONTENT ═══ */}
      <div className="auth-content">
        {/* Plink gradient logo */}
        <h1 className="auth-logo">Plink</h1>

        {/* Slogans */}
        <p className="auth-slogan-ru">Смотрим вместе</p>
        <p className="auth-slogan-en">Watch together. Anywhere. Together.</p>

        {/* Poster arc — 5 cinematic posters */}
        <div className="poster-arc">
          <div className="poster poster-1" title="Pari">
            <span className="poster-title">Pari</span>
          </div>
          <div className="poster poster-2" title="October">
            <span className="poster-title">October</span>
          </div>
          <div className="poster poster-3" title="Super 30">
            <span className="poster-title">Super 30</span>
          </div>
          <div className="poster poster-4" title="Hindi Medium">
            <span className="poster-title">Hindi Medium</span>
          </div>
          <div className="poster poster-5" title="Ra.One">
            <span className="poster-title">Ra.One</span>
          </div>
        </div>

        {/* Silhouette on platform */}
        <div className="silhouette-wrap">
          <div className="silhouette">👤</div>
          <div className="platform" />
        </div>

        {/* Auth card (glassmorphism) */}
        <form className="auth-card" onSubmit={handleSubmit}>
          {isSignUp && (
            <div className="auth-field">
              <svg className="field-icon" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
              </svg>
              <input
                type="text"
                placeholder="Имя пользователя"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
                minLength={3}
                maxLength={32}
                autoComplete="username"
              />
            </div>
          )}

          <div className="auth-field">
            <svg className="field-icon" viewBox="0 0 24 24" fill="currentColor">
              <path d="M20 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z" />
            </svg>
            <input
              type="email"
              placeholder="Email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
            />
          </div>

          <div className="auth-field">
            <svg className="field-icon" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z" />
            </svg>
            <input
              type="password"
              placeholder="Пароль"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={6}
              autoComplete={isSignUp ? 'new-password' : 'current-password'}
            />
          </div>

          {error && <p className="auth-error">{error}</p>}

          <div className="auth-buttons">
            <button type="submit" className="btn-primary" disabled={loading}>
              {loading ? 'Подождите…' : isSignUp ? 'Регистрация' : 'Вход'}
            </button>
            <button
              type="button"
              className="btn-secondary"
              onClick={() => setSignUp(!isSignUp)}
            >
              {isSignUp ? 'Вход' : 'Регистрация'}
            </button>
          </div>
        </form>

        <p className="auth-hint">
          {isSignUp ? 'Уже есть аккаунт?' : 'Нет аккаунта?'}{' '}
          <button type="button" onClick={() => setSignUp(!isSignUp)}>
            {isSignUp ? 'Войти' : 'Создать'}
          </button>
        </p>
      </div>
    </div>
  );
}
