/**
 * Plink Backend — WebSocket Handler (обновлённый)
 * Этап 1: Интеграция security middleware в WS handler.
 * 
 * Копировать в backend: src/websocket/ws-handler.ts
 * 
 * Ключевые изменения (помечены 🔧):
 * 1. senderID/senderName берутся из socket.user (JWT), НЕ из payload
 * 2. play/pause/seek проверяются через isRoomHost()
 * 3. Rate limiting на sync команды
 * 4. Chat текст санитизируется
 */

import { isRoomHost, sanitizeChatMessage, checkRateLimit } from '../middleware/security.js';

export function setupWebSocketHandler(io, prisma, fastify) {

    // ── Аутентификация при подключении ──
    io.use(async (socket, next) => {
        try {
            const token = socket.handshake.auth?.token 
                       || socket.handshake.query?.token;
            if (!token) return next(new Error('No token'));

            const payload = fastify.jwt.verify(token);
            const user = await prisma.user.findUnique({
                where: { id: payload.id },
                select: { id: true, username: true, role: true, bannedUntil: true }
            });

            if (!user) return next(new Error('User not found'));
            if (user.bannedUntil && user.bannedUntil > new Date()) {
                return next(new Error('User banned'));
            }

            socket.user = user; // ← прикрепляем к socket
            next();
        } catch (err) {
            next(new Error('Auth failed'));
        }
    });

    io.on('connection', (socket) => {
        console.log(`[WS] ${socket.user.username} connected`);

        // ── Присоединение к комнате ──
        socket.on('join', async (data) => {
            const { roomId } = data;
            socket.join(roomId);
            socket.activeRoomId = roomId;

            // Уведомить других участников
            socket.to(roomId).emit('participant_update', {
                action: 'joined',
                userID: socket.user.id,       // ← из JWT
                username: socket.user.username, // ← из DB
            });
        });

        // ── Sync команды (play/pause/seek) ──
        socket.on('sync', async (msg) => {
            // 🔧 Rate limit
            if (!checkRateLimit(socket.user.id)) {
                socket.emit('error', { message: 'Rate limit exceeded' });
                return;
            }

            // 🔧 FIX 3.1: Only host can send play/pause/seek
            if (['play', 'pause', 'seek'].includes(msg.command)) {
                const hostCheck = await isRoomHost(prisma, msg.roomID, socket.user.id);
                if (!hostCheck) {
                    socket.emit('error', { 
                        message: 'Only the host can control playback' 
                    });
                    return;
                }
            }

            // 🔧 Перезаписываем senderID из JWT (не доверяем клиенту)
            msg.senderID = socket.user.id;

            // Broadcast другим участникам
            socket.to(msg.roomID).emit('sync', msg);
        });

        // ── Chat сообщения ──
        socket.on('chat', async (msg) => {
            // 🔧 Rate limit
            if (!checkRateLimit(socket.user.id)) {
                socket.emit('error', { message: 'Rate limit exceeded' });
                return;
            }

            // 🔧 FIX 3.3: Server-side identity enforcement
            const safeMsg = await sanitizeChatMessage(msg, socket.user);

            // Сохраняем в БД
            await prisma.chatMessage.create({
                data: {
                    roomID: safeMsg.roomID,
                    senderID: safeMsg.senderID,   // ← из JWT
                    text: safeMsg.text,           // ← sanitized
                }
            });

            // Broadcast
            io.to(safeMsg.roomID).emit('chat', safeMsg);
        });

        // ── Реакции ──
        socket.on('reaction', (msg) => {
            if (!checkRateLimit(socket.user.id)) return;

            // 🔧 Перезаписываем identity
            socket.to(msg.roomID).emit('reaction', {
                ...msg,
                senderID: socket.user.id,
                senderName: socket.user.username,
            });
        });

        // ── Отключение ──
        socket.on('disconnect', () => {
            if (socket.activeRoomId) {
                socket.to(socket.activeRoomId).emit('participant_update', {
                    action: 'left',
                    userID: socket.user.id,
                    username: socket.user.username,
                });
            }
        });
    });
}
