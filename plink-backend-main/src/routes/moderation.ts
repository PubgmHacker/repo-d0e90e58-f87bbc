// User-facing moderation: report, block, list blocked (App Store UGC compliance)
import { prisma } from '../config/db.js';

const REPORT_REASONS = new Set(['spam', 'harassment', 'nsfw', 'other']);

export default async function moderationRoutes(fastify: any) {
  // POST /api/moderation/report
  fastify.post(
    '/moderation/report',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const body = (request.body ?? {}) as {
        targetUserId?: string;
        roomId?: string;
        messageId?: string;
        reason?: string;
        details?: string;
      };

      const reason = (body.reason ?? 'other').toLowerCase();
      if (!REPORT_REASONS.has(reason)) {
        return reply.status(400).send({ error: 'Invalid reason', allowed: [...REPORT_REASONS] });
      }
      if (!body.targetUserId && !body.roomId && !body.messageId) {
        return reply.status(400).send({ error: 'Provide targetUserId, roomId, or messageId' });
      }

      const reasonText = body.details
        ? `${reason}: ${String(body.details).slice(0, 500)}`
        : reason;

      const report = await prisma.report.create({
        data: {
          reporterID: request.user.id,
          roomID: body.roomId ?? null,
          reason: reasonText,
          status: 'pending',
        },
      });

      reply.send({
        success: true,
        id: report.id,
        targetUserId: body.targetUserId ?? null,
        messageId: body.messageId ?? null,
      });
    },
  );

  // POST /api/moderation/block
  fastify.post(
    '/moderation/block',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const { userId } = (request.body ?? {}) as { userId?: string };
      if (!userId) return reply.status(400).send({ error: 'userId required' });
      if (userId === request.user.id) {
        return reply.status(400).send({ error: 'Cannot block yourself' });
      }

      const target = await prisma.user.findUnique({ where: { id: userId }, select: { id: true } });
      if (!target) return reply.status(404).send({ error: 'User not found' });

      await prisma.userBlock.upsert({
        where: {
          blockerID_blockedID: {
            blockerID: request.user.id,
            blockedID: userId,
          },
        },
        create: {
          blockerID: request.user.id,
          blockedID: userId,
        },
        update: {},
      });

      reply.send({ success: true, blockedId: userId });
    },
  );

  // DELETE /api/moderation/block/:userId
  fastify.delete(
    '/moderation/block/:userId',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const { userId } = request.params as { userId: string };
      await prisma.userBlock.deleteMany({
        where: { blockerID: request.user.id, blockedID: userId },
      });
      reply.send({ success: true });
    },
  );

  // GET /api/moderation/blocks
  fastify.get(
    '/moderation/blocks',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const blocks = await prisma.userBlock.findMany({
        where: { blockerID: request.user.id },
        include: {
          blocked: {
            select: { id: true, username: true, avatarURL: true },
          },
        },
        orderBy: { createdAt: 'desc' },
      });

      reply.send(
        blocks.map((b: any) => ({
          id: b.blocked.id,
          username: b.blocked.username,
          avatarURL: b.blocked.avatarURL,
          blockedAt: b.createdAt,
        })),
      );
    },
  );
}
