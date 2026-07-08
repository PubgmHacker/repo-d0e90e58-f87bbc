import { prisma } from '../config/db.js';

export default async function messageRoutes(fastify) {
  fastify.get('/messages/dm/:friendId', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { friendId } = request.params;
    const messages = await prisma.directMessage.findMany({
      where: {
        OR: [
          { senderID: request.user.id, receiverID: friendId },
          { senderID: friendId, receiverID: request.user.id }
        ]
      },
      orderBy: { createdAt: 'asc' },
      take: 100,
    });
    reply.send(messages);
  });

  fastify.post('/messages/dm', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { receiverId, content } = request.body;
    if (!content || content.length > 150) {
      return reply.status(400).send({ error: 'Invalid message' });
    }
    const msg = await prisma.directMessage.create({
      data: { senderID: request.user.id, receiverID: receiverId, content }
    });
    reply.send(msg);
  });
}
