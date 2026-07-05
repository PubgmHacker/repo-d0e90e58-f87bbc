// src/routes/rooms.ts — с Redis кэшем
import { hashRoomPassword, verifyRoomPassword, requireHost } from '../middleware/security.js';
import { cacheGet, cacheSet, cacheDel } from '../config/redis.js';
import { logAudit, AuditActions } from '../utils/audit.js';

const ROOMS_CACHE_KEY = 'rooms:public:50';
const ROOMS_CACHE_TTL = 30; // 30 sec

// 🔧 FIX: mediaItem хранится в БД как JSON-строка (Prisma `String?` колонка).
// iOS ожидает structured object, не строку — иначе decoding падает с typeMismatch
// и весь Room decode ломается. Эта функция парсит строку обратно в объект.
// Применяется во всех endpoints которые возвращают room: create, join, list, get.
//
// 🔧 ROBUSTNESS: try/catch вокруг JSON.parse. Если в БД лежит битая строка
// (исторические данные, partial write и т.п.) — возвращаем null вместо того
// чтобы ронять весь endpoint 500-й. Иначе iOS видит ошибку → myRooms = [] →
// юзер думает что у него нет комнат, хотя они есть.
function serializeRoom(room) {
    if (!room) return null;
    const { password, ...rest } = room;
    let parsedMediaItem = null;
    if (rest.mediaItem) {
        try {
            parsedMediaItem = JSON.parse(rest.mediaItem);
        } catch (e) {
            // Битая JSON-строка — логируем, возвращаем null, не роняем endpoint
            console.warn(`[rooms] Failed to parse mediaItem for room ${rest.id}:`, e.message);
            parsedMediaItem = null;
        }
    }
    return {
        ...rest,
        mediaItem: parsedMediaItem,
    };
}

export default async function roomRoutes(fastify, _options) {
    const { prisma } = fastify;

    // POST /api/rooms — Создание комнаты
    fastify.post('/rooms', {
        preHandler: [fastify.authenticate]
    }, async (request, reply) => {
        const { name, maxParticipants, mediaItem, privacy, password, hostName } = request.body;

        // 🔧 Pack v3 FIX: JWT содержит только {id}, без username.
        // Берём username из БД, fallback на body.hostName, потом 'Unknown'.
        let resolvedHostName = hostName || 'Unknown';
        try {
            const user = await prisma.user.findUnique({
                where: { id: request.user.id },
                select: { username: true }
            });
            if (user?.username) resolvedHostName = user.username;
        } catch {}

        const hashedPassword = password 
            ? await hashRoomPassword(password) 
            : null;

        const room = await prisma.room.create({
            data: {
                name,
                hostID: request.user.id,
                hostName: resolvedHostName,
                code: generateRoomCode(),
                maxParticipants: maxParticipants || 10,
                mediaItem: mediaItem ? JSON.stringify(mediaItem) : null,
                privacy: privacy || 'public',
                password: hashedPassword,
                hostIsPremium: await getUserPremiumStatus(prisma, request.user.id),
                isActive: true,
            }
        });

        // Invalidate cache
        await cacheDel(ROOMS_CACHE_KEY);

        await logAudit({
            userId: request.user.id,
            action: AuditActions.ROOM_CREATE,
            ip: request.ip,
            metadata: { roomId: room.id, roomCode: room.code },
        });

        const { password: _, ...roomWithoutPassword } = room;
        // 🔧 FIX: parse mediaItem JSON string back to object for iOS
        reply.send(serializeRoom(roomWithoutPassword));
    });

    // POST /api/rooms/join — Вход в комнату
    fastify.post('/rooms/join', {
        preHandler: [fastify.authenticate]
    }, async (request, reply) => {
        const { code, password } = request.body;

        const room = await prisma.room.findFirst({
            where: { code: code.toUpperCase(), isActive: true }
        });

        if (!room) return reply.status(404).send({ error: 'Комната не найдена' });

        if (room.password) {
            if (!password) return reply.status(401).send({ error: 'Требуется пароль' });
            const isValid = await verifyRoomPassword(password, room.password);
            if (!isValid) return reply.status(401).send({ error: 'Неверный пароль' });
        }

        const participantCount = await prisma.roomParticipant.count({
            where: { roomID: room.id }
        });
        if (participantCount >= room.maxParticipants) {
            return reply.status(409).send({ error: 'Комната заполнена' });
        }

        await prisma.roomParticipant.create({
            data: { roomID: room.id, userID: request.user.id }
        });

        await logAudit({
            userId: request.user.id,
            action: AuditActions.ROOM_JOIN,
            ip: request.ip,
            metadata: { roomId: room.id, roomCode: room.code },
        });

        const { password: _, ...roomWithoutPassword } = room;
        // 🔧 FIX: parse mediaItem JSON string back to object for iOS
        reply.send(serializeRoom(roomWithoutPassword));
    });

    // DELETE /api/rooms/:id — Удалить комнату (только host или ADMIN)
    //
    // 🔧 NEW: Раньше не было endpoint для удаления комнат — пользователь мог создать
    // комнату, но не мог её удалить. Она висела на главной с 0 участников вечно.
    // Удаляем cascade (schema.prisma: onDelete: Cascade на RoomParticipant, ChatMessage,
    // PlaybackState, WatchHistory, Report, AdBreak — всё удалится автоматически).
    fastify.delete('/rooms/:id', {
        preHandler: [fastify.authenticate]
    }, async (request, reply) => {
        const { id } = request.params;

        const room = await prisma.room.findUnique({ where: { id } });
        if (!room) {
            return reply.status(404).send({ error: 'Комната не найдена' });
        }

        // Только host или ADMIN/FOUNDER может удалить комнату
        const isHost = room.hostID === request.user.id;
        const isAdmin = request.user.role === 'ADMIN' || request.user.role === 'FOUNDER';
        if (!isHost && !isAdmin) {
            return reply.status(403).send({ error: 'Нет прав на удаление комнаты' });
        }

        // Удаляем комнату — каскадно удалятся все связанные записи (participants,
        // messages, playbackState, watchHistory, reports, adBreaks) согласно schema.prisma.
        await prisma.room.delete({ where: { id } });

        // Инвалидируем кэш списка публичных комнат
        await cacheDel(ROOMS_CACHE_KEY);

        await logAudit({
            userId: request.user.id,
            action: AuditActions.ROOM_DELETE,
            ip: request.ip,
            metadata: { roomId: id, roomCode: room.code, roomName: room.name },
        });

        reply.send({ success: true });
    });

    // POST /api/rooms/:id/playback
    fastify.post('/rooms/:id/playback', {
        preHandler: [fastify.authenticate, requireHost(prisma)]
    }, async (request, reply) => {
        const { id } = request.params;
        const { time, isPlaying } = request.body;

        await prisma.playbackState.upsert({
            where: { roomID: id },
            update: { currentTime: time, isPlaying },
            create: { roomID: id, currentTime: time, isPlaying },
        });

        await logAudit({
            userId: request.user.id,
            action: AuditActions.PLAYBACK_CONTROL,
            ip: request.ip,
            metadata: { roomId: id, isPlaying, time },
        });

        reply.send({ success: true });
    });

    // GET /api/rooms — Список публичных комнат (С КЭШЕМ)
    fastify.get('/rooms', {
        preHandler: [fastify.authenticate]
    }, async (request, reply) => {
        // Try cache first
        const cached = await cacheGet<any[]>(ROOMS_CACHE_KEY);
        if (cached) {
            return reply.send(cached);
        }

        const rooms = await prisma.room.findMany({
            where: { isActive: true, privacy: 'public' },
            include: { _count: { select: { participants: true } } },
            orderBy: { createdAt: 'desc' },
            take: 50,
        });

        const safeRooms = rooms.map(r => serializeRoom(r));
        
        // Save to cache
        await cacheSet(ROOMS_CACHE_KEY, safeRooms, ROOMS_CACHE_TTL);
        
        reply.send(safeRooms);
    });

    // GET /api/rooms/mine — Мои комнаты
    fastify.get('/rooms/mine', {
        preHandler: [fastify.authenticate]
    }, async (request, reply) => {
        const rooms = await prisma.room.findMany({
            where: {
                OR: [
                    { hostID: request.user.id },
                    { participants: { some: { userID: request.user.id } } }
                ]
            },
            include: { _count: { select: { participants: true } } },
            orderBy: { createdAt: 'desc' },
        });

        const safeRooms = rooms.map(r => serializeRoom(r));
        reply.send(safeRooms);
    });
}

function generateRoomCode(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return Array.from({ length: 6 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

async function getUserPremiumStatus(prisma, userId: string): Promise<boolean> {
    const user = await prisma.user.findUnique({
        where: { id: userId },
        select: { isPremium: true }
    });
    return user?.isPremium ?? false;
}
