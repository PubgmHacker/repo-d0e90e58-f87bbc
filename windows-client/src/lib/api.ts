import type { AuthResponse, ChatMessage, Friend, MediaItem, Room, TrendingVideo, User } from './types';
import { isTauri } from './tauri';

const REMOTE_API = 'https://plink-backend-production-ef31.up.railway.app/api';
const API_BASE = import.meta.env.VITE_API_BASE
  ?? (import.meta.env.DEV && !isTauri() ? '/api' : REMOTE_API);
const TOKEN_KEY = 'plink_token';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

function buildHeaders(options: RequestInit, auth: boolean): Record<string, string> {
  // Only set JSON content-type when there is a body — empty POST + application/json
  // makes Fastify reject with FST_ERR_CTP_EMPTY_JSON_BODY (leave room, etc.).
  const headers: Record<string, string> = {};
  if (options.body != null) {
    headers['Content-Type'] = 'application/json';
  }
  if (options.headers) {
    const h = new Headers(options.headers);
    h.forEach((v, k) => { headers[k] = v; });
  }
  if (auth) {
    const token = getToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }
  return headers;
}

async function tauriHttp<T>(url: string, options: RequestInit, auth: boolean): Promise<T> {
  const { fetch: tauriFetch, Body, ResponseType } = await import('@tauri-apps/api/http');
  const method = (options.method ?? 'GET').toUpperCase();
  const headers = buildHeaders(options, auth);

  let body: ReturnType<typeof Body.json> | undefined;
  if (options.body && typeof options.body === 'string') {
    body = Body.json(JSON.parse(options.body));
  }

  const res = await tauriFetch<T>(url, {
    method: method as 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE',
    headers,
    body,
    responseType: ResponseType.JSON,
  });

  if (res.status >= 400) {
    const errBody = (res.data ?? {}) as { error?: string };
    throw new Error(errBody.error ?? `HTTP ${res.status}`);
  }
  return res.data as T;
}

async function browserFetch<T>(url: string, options: RequestInit, auth: boolean): Promise<T> {
  const headers = new Headers(options.headers);
  if (options.body != null && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  if (auth) {
    const token = getToken();
    if (token) headers.set('Authorization', `Bearer ${token}`);
  }

  let res: Response;
  try {
    res = await fetch(url, { ...options, headers });
  } catch (err) {
    const hint = err instanceof TypeError
      ? ' (сеть/CORS — пересобери .app или обнови бэкенд)'
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

async function request<T>(
  path: string,
  options: RequestInit = {},
  auth = true,
): Promise<T> {
  const url = `${API_BASE}${path}`;
  if (isTauri()) {
    return tauriHttp<T>(url, options, auth);
  }
  return browserFetch<T>(url, options, auth);
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
    return request<{ results: TrendingVideo[] }>('/media/trending?maxResults=24', {}, false);
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
    return request<{ success?: boolean; ok?: boolean }>(`/rooms/${roomId}/leave`, {
      method: 'POST',
      body: JSON.stringify({}),
    });
  },

  aiChat(message: string) {
    return request<{ message: string; proposedAction?: unknown }>('/ai/chat', {
      method: 'POST',
      body: JSON.stringify({ message }),
    });
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

  // ═══ Moderation API — App Store / Web UGC compliance ═══
  moderationReport(targetUserId: string, reason: string, details = '') {
    return request<{ success: boolean }>('/moderation/report', {
      method: 'POST',
      body: JSON.stringify({ targetUserId, reason, details }),
    });
  },

  moderationBlock(userId: string) {
    return request<{ success: boolean }>('/moderation/block', {
      method: 'POST',
      body: JSON.stringify({ userId }),
    });
  },

  moderationUnblock(userId: string) {
    return request<{ success: boolean }>(`/moderation/block/${userId}`, {
      method: 'DELETE',
    });
  },

  moderationListBlocked() {
    return request<{ blocked: Array<{ id: string; username: string }> }>('/moderation/blocked');
  },
};

export { youtubeMediaItem, parseMediaFromUrl, embedUrlForMedia } from './mediaUrl';