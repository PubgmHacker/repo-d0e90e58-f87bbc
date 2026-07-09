// src/services/presence.ts — Pack 4: Realtime presence + typing indicators
import type { WebSocket } from 'ws';

interface UserPresence {
  userId: string;
  username: string;
  lastSeen: number;
  rooms: Set<string>;
  typing: Map<string, number>; // roomId → timestamp
}

class PresenceService {
  private users = new Map<string, UserPresence>();
  private sockets = new Map<WebSocket, string>(); // socket → userId
  
  /** Зарегистрировать соединение */
  connect(socket: WebSocket, userId: string, username: string) {
    let presence = this.users.get(userId);
    if (!presence) {
      presence = {
        userId,
        username,
        lastSeen: Date.now(),
        rooms: new Set(),
        typing: new Map(),
      };
      this.users.set(userId, presence);
    }
    presence.lastSeen = Date.now();
    this.sockets.set(socket, userId);
  }
  
  /** Зарегистрировать присоединение к комнате */
  joinRoom(socket: WebSocket, roomId: string) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const presence = this.users.get(userId);
    if (!presence) return;
    presence.rooms.add(roomId);
  }
  
  /** Зарегистрировать выход из комнаты */
  leaveRoom(socket: WebSocket, roomId: string) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const presence = this.users.get(userId);
    if (!presence) return;
    presence.rooms.delete(roomId);
    presence.typing.delete(roomId);
  }
  
  /** Отметить что юзер печатает в комнате */
  setTyping(socket: WebSocket, roomId: string) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const presence = this.users.get(userId);
    if (!presence) return;
    presence.typing.set(roomId, Date.now());
  }
  
  /** Кто печатает в комнате */
  getTypingUsers(roomId: string): { userId: string; username: string }[] {
    const result: { userId: string; username: string }[] = [];
    const now = Date.now();
    const TYPING_TIMEOUT = 3000; // 3 sec
    
    for (const presence of this.users.values()) {
      const typingAt = presence.typing.get(roomId);
      if (typingAt && now - typingAt < TYPING_TIMEOUT) {
        result.push({ userId: presence.userId, username: presence.username });
      } else if (typingAt) {
        presence.typing.delete(roomId);
      }
    }
    return result;
  }
  
  /** Кто онлайн в комнате */
  getRoomUsers(roomId: string): { userId: string; username: string }[] {
    const result: { userId: string; username: string }[] = [];
    for (const presence of this.users.values()) {
      if (presence.rooms.has(roomId)) {
        result.push({ userId: presence.userId, username: presence.username });
      }
    }
    return result;
  }
  
  /** Все онлайн пользователи */
  getOnlineUsers(): { userId: string; username: string }[] {
    return Array.from(this.users.values()).map(p => ({
      userId: p.userId,
      username: p.username,
    }));
  }
  
  /** Зарегистрировать disconnect */
  disconnect(socket: WebSocket) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const presence = this.users.get(userId);
    if (presence) {
      presence.lastSeen = Date.now();
    }
    this.sockets.delete(socket);
    
    // Если у юзера нет других сокетов — пометить offline через 30 сек
    setTimeout(() => {
      const stillConnected = Array.from(this.sockets.values()).some(id => id === userId);
      if (!stillConnected) {
        this.users.delete(userId);
      }
    }, 30_000);
  }
  
  /** Heartbeat — обновить lastSeen */
  heartbeat(socket: WebSocket) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const presence = this.users.get(userId);
    if (presence) presence.lastSeen = Date.now();
  }
  
  /** Cleanup — удалить inactive users */
  cleanup() {
    const now = Date.now();
    const TIMEOUT = 5 * 60 * 1000; // 5 min
    
    for (const [userId, presence] of this.users) {
      const stillConnected = Array.from(this.sockets.values()).some(id => id === userId);
      if (!stillConnected && now - presence.lastSeen > TIMEOUT) {
        this.users.delete(userId);
      }
    }
  }
}

export const presence = new PresenceService();

// Cleanup каждые 60 секунд
setInterval(() => presence.cleanup(), 60_000).unref();
