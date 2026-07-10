/**
 * Plink Backend Security Middleware
 * Этап 1: Бэкенд и безопасность (3.1, 3.3, 3.5)
 * 
 * Этот файл содержит server-side middleware для Fastify/WebSocket.
 * Копировать в backend-репозиторий: src/middleware/security.ts
 */

import bcrypt from 'bcrypt';

// ═══════════════════════════════════════════════════════════════════════
// 3.1 — ПРОВЕРКА ПРАВ ХОСТА
// ═══════════════════════════════════════════════════════════════════════

/**
 * Проверяет, является ли пользователь хостом комнаты.
 * Только хост может отправлять play/pause/seek.
 */
export async function isRoomHost(prisma, roomId: string, userId: string): Promise<boolean> {
    const room = await prisma.room.findUnique({
        where: { id: roomId },
        select: { hostID: true }
    });
    return room?.hostID === userId;
}

/**
 * Fastify preHandler для REST маршрутов.
 * Использование:
 *   fastify.post('/rooms/:id/playback', {
 *     preHandler: [fastify.authenticate, requireHost(prisma)]
 *   }, handler)
 */
export function requireHost(prisma) {
    return async (request, reply) => {
        const { id: roomId } = request.params;
        const userId = request.user.id;

        const room = await prisma.room.findUnique({
            where: { id: roomId },
            select: { hostID: true }
        });

        if (!room) return reply.status(404).send({ error: 'Room not found' });
        if (room.hostID !== userId) {
            return reply.status(403).send({ error: 'Only host can control playback' });
        }
    };
}

// ═══════════════════════════════════════════════════════════════════════
// 3.3 — ВАЛИДАЦИЯ SENDERID В ЧАТЕ
// ═══════════════════════════════════════════════════════════════════════

/**
 * Обрабатывает chat-сообщение — ВСЕГДА перезаписывает identity из JWT.
 * Игнорирует client-supplied senderID/senderName.
 * 
 * Использование в ws-handler.ts:
 *   case 'chat':
 *     const safe = sanitizeChatMessage(msg, socket.user, prisma);
 *     io.to(roomId).emit('chat', safe);
 *     break;
 */
export async function sanitizeChatMessage(
    clientMsg: any,
    user: { id: string; username: string; role: string }
) {
    return {
        type: 'chat',
        roomID: clientMsg.roomID,
        id: clientMsg.id || crypto.randomUUID(),
        senderID: user.id,           // ← from JWT
        senderName: user.username,   // ← from DB
        senderRole: user.role,       // ← from DB
        text: sanitizeText(clientMsg.text),
        timestamp: Date.now(),
    };
}

/**
 * Санитизация: HTML strip + 150 char limit + control char removal.
 */
function sanitizeText(text: string): string {
    if (!text || typeof text !== 'string') return '';
    let cleaned = text
        .replace(/<[^>]*>/g, '')
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&').replace(/&quot;/g, '"')
        .replace(/&#x27;/g, "'").replace(/&#x2F;/g, '/');
    if (cleaned.length > 150) cleaned = cleaned.substring(0, 150);
    cleaned = cleaned.replace(/[\x00-\x1F\x7F]/g, '');
    return cleaned.trim();
}

// ═══════════════════════════════════════════════════════════════════════
// 3.5 — ХЕШИРОВАНИЕ ПАРОЛЕЙ КОМНАТ
// ═══════════════════════════════════════════════════════════════════════

const BCRYPT_ROUNDS = 10;

/** Хеширует пароль при создании комнаты. */
export async function hashRoomPassword(plain: string): Promise<string> {
    return bcrypt.hash(plain, BCRYPT_ROUNDS);
}

/** Проверяет пароль при входе. */
export async function verifyRoomPassword(plain: string, hashed: string): Promise<boolean> {
    try { return await bcrypt.compare(plain, hashed); } catch { return false; }
}

// ═══════════════════════════════════════════════════════════════════════
// Rate limiting для WS sync команд (max 10/sec per user)
// ═══════════════════════════════════════════════════════════════════════

const rlMap = new Map<string, { count: number; resetAt: number }>();

export function checkRateLimit(userId: string): boolean {
    const now = Date.now();
    const e = rlMap.get(userId);
    if (!e || now > e.resetAt) {
        rlMap.set(userId, { count: 1, resetAt: now + 1000 });
        return true;
    }
    if (e.count >= 10) return false;
    e.count++;
    return true;
}

setInterval(() => {
    const now = Date.now();
    for (const [k, v] of rlMap) if (now > v.resetAt) rlMap.delete(k);
}, 60_000);
