import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import { config } from './config/index.js';
import { prisma } from './config/db.js';
import { authenticate } from './middleware/auth.js';
import { setupWebSocketHandler } from './websocket/ws-handler.js';
import authRoutes from './routes/auth.js';
import roomRoutes from './routes/rooms.js';
import friendRoutes from './routes/friends.js';
import messageRoutes from './routes/messages.js';
import profileRoutes from './routes/profile.js';
import mediaRoutes from './routes/media.js';

const fastify = Fastify({ logger: { transport: { target: 'pino-pretty' } } });

// ── Decorate prisma ──
fastify.decorate('prisma', prisma);

// ── Plugins ──
await fastify.register(cors, { origin: config.CORS_ORIGIN, credentials: true });
await fastify.register(jwt, { secret: config.JWT_SECRET });
await fastify.register(rateLimit, { max: 100, timeWindow: '1 minute' });
await fastify.register(websocket, { options: { maxPayload: 1048576 } });

// ── Decorate authenticate ──
fastify.decorate('authenticate', authenticate);

// ── Routes ──
await fastify.register(authRoutes, { prefix: '/api' });
await fastify.register(roomRoutes, { prefix: '/api' });
await fastify.register(friendRoutes, { prefix: '/api' });
await fastify.register(messageRoutes, { prefix: '/api' });
await fastify.register(profileRoutes, { prefix: '/api' });
await fastify.register(mediaRoutes, { prefix: '/api' });

// ── WebSocket ──
setupWebSocketHandler(fastify.websocketServer, prisma, fastify);

// ── Health check ──
fastify.get('/health', async () => ({ status: 'ok', timestamp: Date.now() }));

// ── Start ──
const start = async () => {
  try {
    await fastify.listen({ port: config.PORT, host: '0.0.0.0' });
    console.log(`🚀 Plink backend running on port ${config.PORT}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};
start();
