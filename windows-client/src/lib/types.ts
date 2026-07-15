export interface User {
  id: string;
  username: string;
  email: string;
  avatarURL?: string | null;
  avatarData?: string | null;
  isPremium?: boolean;
  role?: string;
}

export interface AuthResponse {
  token: string;
  refreshToken: string;
  accessExpiresAt?: string;
  user: User;
}

export interface MediaItem {
  id: string;
  title: string;
  artist?: string | null;
  thumbnailURL?: string | null;
  streamURL: string;
  duration?: number | null;
  mediaType: 'video' | 'audio';
  source: 'youtube' | 'vk' | 'rutube' | 'external';
  videoId?: string;
}

export interface Room {
  id: string;
  name: string;
  code: string;
  hostID: string;
  hostName: string;
  maxParticipants: number;
  mediaItem?: MediaItem | null;
  isActive: boolean;
  participantCount?: number;
}

export interface TrendingVideo {
  id: string;
  title: string;
  thumbnailURL?: string;
  channelTitle?: string;
}

export interface Friend {
  id: string;
  username: string;
  avatarURL?: string | null;
  isOnline: boolean;
  friendsSince?: string;
}

export interface ChatMessage {
  id: string;
  senderID: string;
  text: string;
  createdAt: string;
  clientMessageId?: string;
}