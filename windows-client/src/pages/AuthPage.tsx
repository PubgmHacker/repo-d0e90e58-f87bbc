import { useState } from 'react';
import type { FormEvent } from 'react';
import { api, setToken } from '../lib/api';
import type { User } from '../lib/types';

type Props = {
  onAuth: (user: User, token: string) => void;
};

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
      setError(err instanceof Error ? err.message : 'Auth failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <h1>Plink</h1>
        <p className="subtitle">Смотри вместе — Windows</p>
        <form onSubmit={handleSubmit}>
          {mode === 'signup' && (
            <input
              placeholder="Username (5-32 chars)"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
            />
          )}
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
          />
          {error && <p className="error">{error}</p>}
          <button type="submit" disabled={loading}>
            {loading ? '...' : mode === 'signin' ? 'Войти' : 'Регистрация'}
          </button>
        </form>
        <button className="link-btn" type="button" onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}>
          {mode === 'signin' ? 'Создать аккаунт' : 'Уже есть аккаунт?'}
        </button>
      </div>
    </div>
  );
}