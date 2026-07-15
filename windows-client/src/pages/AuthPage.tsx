import { useState } from 'react';
import type { FormEvent } from 'react';
import { api, setToken } from '../lib/api';
import type { User } from '../lib/types';
import { PosterMosaic } from '../components/auth/PosterMosaic';

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
    <div className="auth-page cinematic-auth">
      <PosterMosaic />
      <div className="auth-form-panel">
        <div className="auth-card">
          <h1>{mode === 'signin' ? 'Welcome back' : 'Create account'}</h1>
          <p className="auth-sub">Watch together with friends — iOS, Mac & Windows</p>
          <form onSubmit={handleSubmit}>
            {mode === 'signup' && (
              <>
                <label htmlFor="username">Username</label>
                <input
                  id="username"
                  placeholder="yourname"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                  minLength={5}
                  maxLength={32}
                />
              </>
            )}
            <label htmlFor="email">Email</label>
            <input
              id="email"
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
            />
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={6}
            />
            {error && <p className="error banner">{error}</p>}
            <button type="submit" className="submit-btn" disabled={loading}>
              {loading ? 'Please wait…' : mode === 'signin' ? 'Sign in' : 'Get started'}
            </button>
          </form>
          <button className="link-btn" type="button" onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}>
            {mode === 'signin' ? 'New here? Create an account' : 'Already have an account? Sign in'}
          </button>
        </div>
      </div>
    </div>
  );
}