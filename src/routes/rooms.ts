// src/routes/rooms.ts — с Redis кэшем
import { hashRoomPassword, verifyRoomPassword, requireHost } from '../middleware/security.js';
import { cacheGet, cacheSet, cacheDel } from '../config/redis.js';
import { logAudit, AuditActions } from '../utils/audit.js';

const ROOMS_CACHE_KEY = 'rooms:public:50';
const ROOMS_CACHE_TTL = 30; // 30 sec

export default async function roomRoutes(fastify, _options) {
    const { prisma } = fastify;

    // POST /api/rooms — Создание комнаты
    fastify.post('/rooms', {
        preHandler: [fastify.authenticate]
    }, async (request, reply) => {
        const { name, maxParticipants, mediaItem, privacy, password } = request.body;

        const hashedPassword = password 
            ? await hashRoomPassword(password) 
            : null;

        const room = await prisma.room.create({
            data: {
                name,
                hostID: request.user.id,
                hostName: request.user.username,
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
        reply.send(roomWithoutPassword);
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
        reply.send(roomWithoutPassword);
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

        const safeRooms = rooms.map(({ password, ...r }) => r);
        
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

        const safeRooms = rooms.map(({ password, ...r }) => r);
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
