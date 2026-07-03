import type { WebSocket } from 'ws';
import { isRoomHost, checkRateLimit } from '../middleware/security.js';
import { sanitizeChatMessage } from '../middleware/security.js';

interface PlinkSocket extends WebSocket {
  userId?: string;
  username?: string;
  role?: string;
  activeRoomId?: string;
}

const rooms = new Map<string, Set<PlinkSocket>>();

export function setupWebSocketHandler(io, prisma, fastify) {
  io.on('connection', async (socket: PlinkSocket, req: any) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const token = url.searchParams.get('token');
      const roomIdFromQuery = url.searchParams.get('roomId');

      // Также пытаемся достать roomId из пути /ws/room/:id
      const pathParts = url.pathname.split('/');
      const roomIdFromPath = pathParts.length >= 4 && pathParts[2] === 'room'
        ? pathParts[3]
        : null;

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

      console.log(`[WS] ${user.username} connected`);

      // Авто-присоединение к комнате если roomId указан в URL
      if (roomId) {
        socket.activeRoomId = roomId;
        if (!rooms.has(roomId)) rooms.set(roomId, new Set());
        rooms.get(roomId)!.add(socket);
        broadcast(roomId, {
          type: 'participant_update',
          action: 'joined',
          userId: user.id,
          username: user.username,
          roomId,
        }, socket);
      }

      socket.on('message', async (raw: Buffer) => {
        let msg: any;
        try {
          msg = JSON.parse(raw.toString());
        } catch {
          socket.send(JSON.stringify({ type: 'error', message: 'Invalid JSON' }));
          return;
        }

        // ─── 1. Heartbeat ping/pong ───
        if (msg.command === 'ping') {
          socket.send(JSON.stringify({
            command: 'pong',
            timestamp: msg.timestamp,
            serverTimestamp: Date.now() / 1000,
          }));
          return;
        }

        // ─── 2. Signaling (WebRTC) — просто пробрасываем в комнату ───
        if (msg.kind && msg.roomId) {
          broadcast(msg.roomId, msg, socket);
          return;
        }

        // ─── 3. Chat ───
        if (msg.type === 'chat') {
          if (!checkRateLimit(user.id)) {
            socket.send(JSON.stringify({ type: 'error', message: 'Rate limit exceeded' }));
            return;
          }
          const safeMsg = await sanitizeChatMessage(msg, user);
          try {
            await prisma.chatMessage.create({
              data: { roomID: safeMsg.roomID, senderID: safeMsg.senderID, text: safeMsg.text },
            });
          } catch (e) {
            console.error('[WS] chat save error', e);
          }
          broadcast(safeMsg.roomID, safeMsg);
          return;
        }

        // ─── 4. Reaction ───
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

        // ─── 5. Sync (play/pause/seek/changeMedia/stateRequest/stateResponse/correction) ───
        if (msg.command && msg.roomID) {
          if (!checkRateLimit(user.id)) {
            socket.send(JSON.stringify({ type: 'error', message: 'Rate limit exceeded' }));
            return;
          }
          // Только хост может слать play/pause/seek/changeMedia
          if (['play', 'pause', 'seek', 'changeMedia', 'correction'].includes(msg.command)) {
            const isHost = await isRoomHost(prisma, msg.roomID, user.id);
            if (!isHost) {
              socket.send(JSON.stringify({
                type: 'error',
                message: 'Only the host can control playback',
              }));
              return;
            }
          }
          // Перезаписываем senderID из JWT
          msg.senderID = user.id;
          broadcast(msg.roomID, msg, socket);
          return;
        }

        // ─── 6. Ad command ───
        if (msg.command && msg.roomID && msg.command?.type) {
          broadcast(msg.roomID, msg, socket);
          return;
        }
      });

      socket.on('close', () => {
        if (socket.activeRoomId && rooms.has(socket.activeRoomId)) {
          rooms.get(socket.activeRoomId)!.delete(socket);
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
}

function broadcast(roomId: string, payload: any, exclude?: PlinkSocket) {
  const room = rooms.get(roomId);
  if (!room) return;
  const msg = JSON.stringify(payload);
  for (const s of room) {
    if (s === exclude) continue;
    if (s.readyState === s.OPEN) s.send(msg);
  }
}
