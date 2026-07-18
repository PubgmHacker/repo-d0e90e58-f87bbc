// src/websocket/ws-handler.ts — Pack 4: с presence, typing, room state recovery
import type { WebSocket } from 'ws';
import { isRoomHost, checkRateLimit, sanitizeChatMessage } from '../middleware/security.js';
import { presence } from '../services/presence.js';
import { wsConnections, wsMessages, usersOnline, messagesSent } from '../services/metrics.js';

interface PlinkSocket extends WebSocket {
  userId?: string;
  username?: string;
  role?: string;
  activeRoomId?: string;
}

const rooms = new Map<string, Set<PlinkSocket>>();
const roomStates = new Map<string, {
  mediaTime: number;
  isPlaying: boolean;
  mediaItem: any;
  updatedAt: number;
}>();

export function setupWebSocketHandler(io, prisma, fastify) {
  io.on('connection', async (socket: PlinkSocket, req: any) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const token = url.searchParams.get('token');
      const roomIdFromQuery = url.searchParams.get('roomId');

      const pathParts = url.pathname.split('/');
      const roomIdFromPath = pathParts.length >= 4 && pathParts[2] === 'room'
        ? pathParts[3] : null;

      const roomId = roomIdFromPath || roomIdFromQuery;

      if (!token) {
        socket.close(4001, 'No token');
        return;
      }

      let payload: any;
      try {
        payload = fastify.jwt.verify(token);
      } catch {
        socket.close(4001, 'Invalid token');
        return;
      }

      const user = await prisma.user.findUnique({
        where: { id: payload.id },
        select: { id: true, username: true, role: true, bannedUntil: true },
      });

      if (!user) {
        socket.close(4001, 'User not found');
        return;
      }
      if (user.bannedUntil && user.bannedUntil > new Date()) {
        socket.close(4003, 'User banned');
        return;
      }

      socket.userId = user.id;
      socket.username = user.username;
      socket.role = user.role;

      presence.connect(socket, user.id, user.username);
      wsConnections.inc();
      usersOnline.set(presence.getOnlineUsers().length);

      console.log(`[WS] ${user.username} connected`);

      if (roomId) {
        joinRoom(socket, roomId, user);
      }

      socket.on('message', async (raw: Buffer) => {
        let msg: any;
        try {
          msg = JSON.parse(raw.toString());
        } catch {
          socket.send(JSON.stringify({ type: 'error', message: 'Invalid JSON' }));
          return;
        }

        wsMessages.inc({ type: msg.command || msg.type || msg.action || 'unknown', direction: 'in' });
        presence.heartbeat(socket);

        if (msg.command === 'ping') {
          socket.send(JSON.stringify({
            command: 'pong',
            timestamp: msg.timestamp,
            serverTimestamp: Date.now() / 1000,
          }));
          return;
        }

        if (msg.type === 'typing' && msg.roomId) {
          presence.setTyping(socket, msg.roomId);
          const typingUsers = presence.getTypingUsers(msg.roomId);
          broadcast(msg.roomId, {
            type: 'typing_update',
            roomId: msg.roomId,
            typingUsers,
          }, socket);
          return;
        }

        if (msg.type === 'presence_request' && msg.roomId) {
          socket.send(JSON.stringify({
            type: 'presence_response',
            roomId: msg.roomId,
            users: presence.getRoomUsers(msg.roomId),
          }));
          return;
        }

        if (msg.kind && msg.roomId) {
          broadcast(msg.roomId, msg, socket);
          return;
        }

        if (msg.type === 'chat') {
          if (!checkRateLimit(user.id)) {
            socket.send(JSON.stringify({ type: 'error', message: 'Rate limit exceeded' }));
            return;
          }
          const safeMsg = await sanitizeChatMessage(msg, user, prisma);
          try {
            await prisma.chatMessage.create({
              data: { roomID: safeMsg.roomID, senderID: safeMsg.senderID, text: safeMsg.text },
            });
            messagesSent.inc();
          } catch (e) {
            console.error('[WS] chat save error', e);
          }
          broadcast(safeMsg.roomID, safeMsg);
          return;
        }

        if (msg.action === 'send_reaction') {
          if (!checkRateLimit(user.id)) return;
          broadcast(msg.roomId, {
            action: 'reaction',
            emoji: msg.emoji,
            roomId: msg.roomId,
            senderId: user.id,
            senderName: user.username,
          }, socket);
          return;
        }

        if (msg.command && msg.roomID) {
          if (!checkRateLimit(user.id)) {
            socket.send(JSON.stringify({ type: 'error', message: 'Rate limit exceeded' }));
            return;
          }
          
          if (['play', 'pause', 'seek', 'changeMedia', 'correction'].includes(msg.command)) {
            const isHost = await isRoomHost(prisma, msg.roomID, user.id);
            if (!isHost) {
              socket.send(JSON.stringify({
                type: 'error',
                message: 'Only the host can control playback',
              }));
              return;
            }
            if (msg.command === 'play' || msg.command === 'pause' || msg.command === 'seek') {
              roomStates.set(msg.roomID, {
                mediaTime: msg.mediaTime || 0,
                isPlaying: msg.command === 'play',
                mediaItem: null,
                updatedAt: Date.now(),
              });
            }
          }
          
          msg.senderID = user.id;
          broadcast(msg.roomID, msg, socket);
          return;
        }

        if (msg.command === 'stateRequest' && msg.roomID) {
          const state = roomStates.get(msg.roomID);
          if (state) {
            socket.send(JSON.stringify({
              command: 'stateResponse',
              roomID: msg.roomID,
              mediaTime: state.mediaTime + (state.isPlaying ? (Date.now() - state.updatedAt) / 1000 : 0),
              isPlaying: state.isPlaying,
              mediaItem: state.mediaItem,
              timestamp: Date.now() / 1000,
            }));
          }
          return;
        }

        if (msg.command && msg.roomID && msg.command?.type) {
          broadcast(msg.roomID, msg, socket);
          return;
        }
      });

      socket.on('close', () => {
        wsConnections.dec();
        presence.disconnect(socket);
        usersOnline.set(presence.getOnlineUsers().length);
        
        if (socket.activeRoomId && rooms.has(socket.activeRoomId)) {
          rooms.get(socket.activeRoomId)!.delete(socket);
          presence.leaveRoom(socket, socket.activeRoomId);
          broadcast(socket.activeRoomId, {
            type: 'participant_update',
            action: 'left',
            userId: user.id,
            username: user.username,
            roomId: socket.activeRoomId,
          });
        }
      });
    } catch (err) {
      console.error('[WS] setup error', err);
      socket.close(1011, 'Server error');
    }
  });

  setInterval(() => {
    usersOnline.set(presence.getOnlineUsers().length);
  }, 30_000).unref();
}

function joinRoom(socket: PlinkSocket, roomId: string, user: any) {
  socket.activeRoomId = roomId;
  if (!rooms.has(roomId)) rooms.set(roomId, new Set());
  rooms.get(roomId)!.add(socket);
  presence.joinRoom(socket, roomId);
  
  broadcast(roomId, {
    type: 'participant_update',
    action: 'joined',
    userId: user.id,
    username: user.username,
    roomId,
  }, socket);
  
  socket.send(JSON.stringify({
    type: 'presence_response',
    roomId,
    users: presence.getRoomUsers(roomId),
  }));
}

function broadcast(roomId: string, payload: any, exclude?: PlinkSocket) {
  const room = rooms.get(roomId);
  if (!room) return;
  const msg = JSON.stringify(payload);
  for (const s of room) {
    if (s === exclude) continue;
    if (s.readyState === s.OPEN) s.send(msg);
  }
  wsMessages.inc({ 
    type: payload.command || payload.type || payload.action || 'unknown', 
    direction: 'out' 
  });
}
