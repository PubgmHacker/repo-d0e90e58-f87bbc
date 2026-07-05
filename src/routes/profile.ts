import { prisma } from '../config/db.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default async function profileRoutes(fastify) {
  // 🔧 NEW: POST /users/me/avatar — upload avatar as base64, save to disk,
  // return public URL. Stored in /uploads/avatars/USER_ID.jpg.
  fastify.post('/users/me/avatar', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { avatar } = request.body;

    if (!avatar || typeof avatar !== 'string') {
      return reply.status(400).send({ error: 'Avatar data required' });
    }

    // Remove data:image/jpeg;base64, prefix if present
    const base64Data = avatar.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(base64Data, 'base64');

    // Create uploads directory if it doesn't exist
    const uploadsDir = path.join(__dirname, '..', '..', 'uploads', 'avatars');
    if (!fs.existsSync(uploadsDir)) {
      fs.mkdirSync(uploadsDir, { recursive: true });
    }

    // Save as USER_ID.jpg
    const filename = `${request.user.id}.jpg`;
    const filepath = path.join(uploadsDir, filename);
    fs.writeFileSync(filepath, buffer);

    // Public URL — served by Fastify static plugin or Railway
    const avatarURL = `https://plink-backend-production-ef31.up.railway.app/uploads/avatars/${filename}`;

    // Update user in DB
    await prisma.user.update({
      where: { id: request.user.id },
      data: { avatarURL }
    });

    reply.send({ avatarURL });
  });

  // Serve uploaded files
  fastify.get('/uploads/*', async (request, reply) => {
    const filePath = path.join(__dirname, '..', '..', request.url);
    if (fs.existsSync(filePath)) {
      reply.type('image/jpeg').send(fs.createReadStream(filePath));
    } else {
      reply.status(404).send({ error: 'File not found' });
    }
  });
  fastify.get('/users/me', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { id: true, username: true, email: true, avatarURL: true, isPremium: true, premiumUntil: true, role: true, createdAt: true }
    });
    reply.send(user);
  });

  // 🔧 Pack v3: PATCH /users/me — обновление username + avatarURL
  fastify.patch('/users/me', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { username, avatarURL } = request.body;
    const data: any = {};
    if (username && username.trim().length >= 2) data.username = username.trim();
    if (avatarURL !== undefined) data.avatarURL = avatarURL;

    if (Object.keys(data).length === 0) {
      return reply.status(400).send({ error: 'No fields to update' });
    }

    // Проверка уникальности username
    if (data.username) {
      const existing = await prisma.user.findFirst({
        where: { username: data.username, NOT: { id: request.user.id } }
      });
      if (existing) return reply.status(409).send({ error: 'Username already taken' });
    }

    const updated = await prisma.user.update({
      where: { id: request.user.id },
      data,
      select: { id: true, username: true, email: true, avatarURL: true, isPremium: true, premiumUntil: true, role: true, createdAt: true }
    });
    reply.send(updated);
  });

  // 🔧 Pack v3: DELETE /users/me — полное удаление аккаунта (cascade)
  fastify.delete('/users/me', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    try {
      // Cascade delete через Prisma — все связанные записи удалятся автоматически
      // (Room, RoomParticipant, ChatMessage, DirectMessage, FriendRequest, Friendship,
      //  WatchHistory, PlaybackState, Subscription, UserBlock, Report, RefreshToken, AuditLog)
      await prisma.user.delete({ where: { id: request.user.id } });
      reply.send({ deleted: true });
    } catch (e) {
      reply.status(500).send({ error: 'Failed to delete account: ' + e.message });
    }
  });

  fastify.get('/users/:id', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { id } = request.params;
    const user = await prisma.user.findUnique({
      where: { id },
      select: { id: true, username: true, avatarURL: true, isOnline: true }
    });
    if (!user) return reply.status(404).send({ error: 'User not found' });
    reply.send(user);
  });

  fastify.post('/users/me/create-subscription', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { plan } = request.body;
    const expiresAt = new Date();
    expiresAt.setMonth(expiresAt.getMonth() + 1);

    await prisma.user.update({
      where: { id: request.user.id },
      data: { isPremium: true, premiumUntil: expiresAt }
    });
    await prisma.subscription.create({
      data: { userID: request.user.id, plan: plan || 'monthly', expiresAt }
    });
    reply.send({ success: true, expiresAt });
  });

  fastify.get('/users/me/history', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const history = await prisma.watchHistory.findMany({
      where: { userID: request.user.id },
      orderBy: { watchedAt: 'desc' },
      take: 50,
    });
    reply.send(history);
  });
}
