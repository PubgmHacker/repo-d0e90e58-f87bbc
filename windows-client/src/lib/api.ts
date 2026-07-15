import type { AuthResponse, ChatMessage, Friend, MediaItem, Room, TrendingVideo, User } from './types';

const API_BASE = import.meta.env.VITE_API_BASE ?? 'https://plink-backend-production-ef31.up.railway.app/api';
const TOKEN_KEY = 'plink_token';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

async function request<T>(
  path: string,
  options: RequestInit = {},
  auth = true,
): Promise<T> {
  const headers = new Headers(options.headers);
  headers.set('Content-Type', 'application/json');
  if (auth) {
    const token = getToken();
    if (token) headers.set('Authorization', `Bearer ${token}`);
  }

  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  } catch (err) {
    const hint = err instanceof TypeError
      ? ' (сеть/CORS — обнови бэкенд и пересобери .app)'
      : '';
    throw new Error(`Load failed${hint}`);
  }
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error ?? `HTTP ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

export const api = {
  signIn(email: string, password: string) {
    return request<AuthResponse>('/auth/signin', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }, false);
  },

  signUp(email: string, password: string, username: string) {
    return request<AuthResponse>('/auth/signup', {
      method: 'POST',
      body: JSON.stringify({ email, password, username }),
    }, false);
  },

  getMe() {
    return request<User>('/users/me');
  },

  getTrending() {
    return request<{ results: TrendingVideo[] }>('/media/trending?maxResults=10', {}, false);
  },

  getRooms() {
    return request<Room[]>('/rooms');
  },

  createRoom(name: string, mediaItem: MediaItem) {
    return request<Room>('/rooms', {
      method: 'POST',
      body: JSON.stringify({
        name,
        maxParticipants: 10,
        mediaItem,
        privacy: 'public',
      }),
    });
  },

  joinRoom(code: string) {
    return request<Room>('/rooms/join', {
      method: 'POST',
      body: JSON.stringify({ code }),
    });
  },

  leaveRoom(roomId: string) {
    return request<{ ok: boolean }>(`/rooms/${roomId}/leave`, { method: 'POST' });
  },

  getParticipants(roomId: string) {
    return request<{ participants: Array<{ userId: string; username: string; avatarURL?: string }> }>(
      `/rooms/${roomId}/participants`,
    );
  },

  getMessages(roomId: string) {
    return request<{ messages: ChatMessage[]; nextCursor: string | null }>(
      `/rooms/${roomId}/messages?limit=50`,
    );
  },

  getRealtimeTicket(roomId: string) {
    return request<{ ticket: string; expiresInSec: number; protocol: string[] }>(
      '/realtime/ticket',
      { method: 'POST', body: JSON.stringify({ roomId }) },
    );
  },

  getFriends() {
    return request<Friend[]>('/friends');
  },

  uploadAvatar(dataUrl: string) {
    return request<{ avatarData: string; avatarURL: string }>('/users/me/avatar', {
      method: 'POST',
      body: JSON.stringify({ avatar: dataUrl }),
    });
  },
};

export function youtubeMediaItem(videoId: string, title: string, thumbnailURL?: string): MediaItem {
  const embed = `https://www.youtube.com/embed/${videoId}`;
  return {
    id: embed,
    title,
    thumbnailURL: thumbnailURL ?? `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
    streamURL: embed,
    mediaType: 'video',
    source: 'youtube',
    videoId,
  };
}