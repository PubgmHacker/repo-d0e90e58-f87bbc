// src/index.ts — обновлённый с Sentry, Redis, extended healthcheck
import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import * as Sentry from '@sentry/node';
import { config } from './config/index.js';
import { prisma } from './config/db.js';
import { checkRedis } from './config/redis.js';
import { authenticate } from './middleware/auth.js';
import { setupWebSocketHandler } from './websocket/ws-handler.js';
import authRoutes from './routes/auth.js';
import roomRoutes from './routes/rooms.js';
import friendRoutes from './routes/friends.js';
import messageRoutes from './routes/messages.js';
import profileRoutes from './routes/profile.js';
import mediaRoutes from './routes/media.js';
import { alertCritical } from './utils/alerting.js';

// ── Sentry init (если задан DSN) ──
if (config.SENTRY_DSN) {
  Sentry.init({
    dsn: config.SENTRY_DSN,
    environment: config.NODE_ENV,
    tracesSampleRate: config.isProduction ? 0.1 : 1.0,
    profilesSampleRate: config.isProduction ? 0.1 : 1.0,
  });
  console.log('✅ Sentry initialized');
}

const fastify = Fastify({
  logger: {
    level: config.isProduction ? 'info' : 'debug',
    transport: config.isProduction ? undefined : { target: 'pino-pretty' },
    redact: ['req.headers.authorization', 'req.body.password', '*.password'],
  },
});

// ── Decorate ──
fastify.decorate('prisma', prisma);

// ── Plugins ──
await fastify.register(cors, { origin: config.CORS_ORIGIN, credentials: true });
await fastify.register(jwt, { secret: config.JWT_SECRET });
await fastify.register(rateLimit, {
  global: false,
  max: 100,
  timeWindow: '1 minute',
  cache: 10000,
  ban: 5, // ban IP after 5 rate-limit violations
});
await fastify.register(websocket, { options: { maxPayload: 1048576 } });

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

// ── Health check (расширенный) ──
fastify.get('/health', async () => {
  const db = await checkDatabase();
  const redis = await checkRedis();
  return {
    status: db ? 'ok' : 'degraded',
    timestamp: Date.now(),
    uptime: process.uptime(),
    version: process.env.npm_package_version || '1.0.0',
    environment: config.NODE_ENV,
    services: {
      database: db ? 'up' : 'down',
      redis: redis ? 'up' : (config.REDIS_URL ? 'down' : 'not_configured'),
    },
    memory: {
      rss: process.memoryUsage().rss,
      heapUsed: process.memoryUsage().heapUsed,
      heapTotal: process.memoryUsage().heapTotal,
    },
  };
});

async function checkDatabase(): Promise<boolean> {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}

// ── Error handler ──
fastify.setErrorHandler((error, request, reply) => {
  if (error.statusCode >= 500) {
    Sentry.captureException(error);
    alertCritical('Server error', error);
  }
  reply.status(error.statusCode || 500).send({
    error: error.message || 'Internal Server Error',
    statusCode: error.statusCode || 500,
  });
});

// ── Start ──
const start = async () => {
  try {
    await fastify.listen({ port: config.PORT, host: '0.0.0.0' });
    console.log(`🚀 Plink backend running on port ${config.PORT} [${config.NODE_ENV}]`);
  } catch (err) {
    Sentry.captureException(err);
    await alertCritical('Backend failed to start', err as Error);
    fastify.log.error(err);
    process.exit(1);
  }
};

// ── Graceful shutdown ──
const shutdown = async (signal: string) => {
  console.log(`\n${signal} received, shutting down...`);
  await fastify.close();
  await prisma.$disconnect();
  process.exit(0);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// ── Catch uncaught errors ──
process.on('uncaughtException', async (err) => {
  Sentry.captureException(err);
  await alertCritical('Uncaught exception', err);
  console.error('Uncaught:', err);
});

process.on('unhandledRejection', async (reason) => {
  Sentry.captureException(reason as Error);
  await alertCritical('Unhandled rejection', reason as Error);
  console.error('Unhandled rejection:', reason);
});

start();
