import type { WebSocket } from 'ws';
import { isRoomHost, sanitizeChatMessage, checkRateLimit } from '../middleware/security.js';

interface PlinkSocket extends WebSocket {
  userId?: string;
  username?: string;
  activeRoomId?: string;
}

const rooms = new Map<string, Set<PlinkSocket>>();

export function setupWebSocketHandler(io, prisma, fastify) {
  io.on('connection', async (socket: PlinkSocket, req: any) => {
    try {
      // ── Аутентификация по query-параметру token ──
      const url = new URL(req.url, 'http://localhost');
      const token = url.searchParams.get('token');

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

      console.log(`[WS] ${user.username} connected`);

      socket.on('message', async (raw: Buffer) => {
        let msg: any;
        try {
          msg = JSON.parse(raw.toString());
        } catch {
          socket.send(JSON.stringify({ type: 'error', message: 'Invalid JSON' }));
          return;
        }

        const { type, data } = msg;

        switch (type) {
          case 'join': {
            const roomId = data.roomId;
            socket.activeRoomId = roomId;

            if (!rooms.has(roomId)) rooms.set(roomId, new Set());
            rooms.get(roomId)!.add(socket);

            broadcast(roomId, {
              type: 'participant_update',
              data: { action: 'joined', userID: user.id, username: user.username },
            }, socket);
            break;
          }

          case 'sync': {
            if (!checkRateLimit(user.id)) {
              socket.send(JSON.stringify({ type: 'error', message: 'Rate limit exceeded' }));
              return;
            }
            if (['play', 'pause', 'seek'].includes(data.command)) {
              const isHost = await isRoomHost(prisma, data.roomID, user.id);
              if (!isHost) {
                socket.send(JSON.stringify({
                  type: 'error',
                  message: 'Only the host can control playback',
                }));
                return;
              }
            }
            data.senderID = user.id;
            broadcast(data.roomID, { type: 'sync', data }, socket);
            break;
          }

          case 'chat': {
            if (!checkRateLimit(user.id)) {
              socket.send(JSON.stringify({ type: 'error', message: 'Rate limit exceeded' }));
              return;
            }
            const safeMsg = await sanitizeChatMessage(data, user);
            await prisma.chatMessage.create({
              data: { roomID: safeMsg.roomID, senderID: safeMsg.senderID, text: safeMsg.text },
            });
            broadcast(safeMsg.roomID, { type: 'chat', data: safeMsg });
            break;
          }

          case 'reaction': {
            if (!checkRateLimit(user.id)) return;
            broadcast(data.roomID, {
              type: 'reaction',
              data: { ...data, senderID: user.id, senderName: user.username },
            }, socket);
            break;
          }
        }
      });

      socket.on('close', () => {
        if (socket.activeRoomId && rooms.has(socket.activeRoomId)) {
          rooms.get(socket.activeRoomId)!.delete(socket);
          broadcast(socket.activeRoomId, {
            type: 'participant_update',
            data: { action: 'left', userID: user.id, username: user.username },
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
