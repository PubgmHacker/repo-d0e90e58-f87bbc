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

export function ProfilePage({ user, onUserUpdate, onLogout, onBack }: Props) {
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

  return (
    <div className="page profile-page">
      <div className="profile-card glass-panel">
        <div className="avatar-ring">
          {user.avatarURL ? (
            <img src={user.avatarURL} alt="" className="avatar" />
          ) : (
            <div className="avatar avatar-fallback">{user.username[0]?.toUpperCase()}</div>
          )}
        </div>
        <h3>{user.username}</h3>
        <p className="muted">My Library</p>
        <p>{user.email}</p>

        <label className="upload-btn">
          {uploading ? 'Uploading…' : 'Change avatar'}
          <input type="file" accept="image/*" hidden onChange={onAvatarPick} />
        </label>

        {error && <p className="error">{error}</p>}

        <div className="profile-actions">
          <button type="button" className="pro-btn" onClick={onBack}>Back to Home</button>
          <button type="button" className="pro-btn danger" onClick={logout}>Sign out</button>
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