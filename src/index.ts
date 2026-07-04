// src/index.ts — Pack 3: добавлена регистрация billing routes
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
import billingRoutes from './routes/billing.js';  // ← Pack 3
import { alertCritical } from './utils/alerting.js';

if (config.SENTRY_DSN) {
  Sentry.init({
    dsn: config.SENTRY_DSN,
    environment: config.NODE_ENV,
    tracesSampleRate: config.isProduction ? 0.1 : 1.0,
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

fastify.decorate('prisma', prisma);

await fastify.register(cors, { origin: config.CORS_ORIGIN, credentials: true });
await fastify.register(jwt, { secret: config.JWT_SECRET });
await fastify.register(rateLimit, {
  global: false,
  max: 100,
  timeWindow: '1 minute',
  cache: 10000,
  ban: 5,
});
await fastify.register(websocket, { options: { maxPayload: 1048576 } });

fastify.decorate('authenticate', authenticate);

await fastify.register(authRoutes, { prefix: '/api' });
await fastify.register(roomRoutes, { prefix: '/api' });
await fastify.register(friendRoutes, { prefix: '/api' });
await fastify.register(messageRoutes, { prefix: '/api' });
await fastify.register(profileRoutes, { prefix: '/api' });
await fastify.register(mediaRoutes, { prefix: '/api' });
await fastify.register(billingRoutes, { prefix: '/api' });  // ← Pack 3

setupWebSocketHandler(fastify.websocketServer, prisma, fastify);

fastify.get('/health', async () => {
  const db = await checkDatabase();
  const redis = await checkRedis();
  return {
    status: db ? 'ok' : 'degraded',
    timestamp: Date.now(),
    uptime: process.uptime(),
    version: '1.3.0',
    environment: config.NODE_ENV,
    services: {
      database: db ? 'up' : 'down',
      redis: redis ? 'up' : (config.REDIS_URL ? 'down' : 'not_configured'),
      yt_dlp: 'available',
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

const start = async () => {
  try {
    await fastify.listen({ port: config.PORT, host: '0.0.0.0' });
    console.log(`🚀 Plink backend v1.3.0 running on port ${config.PORT} [${config.NODE_ENV}]`);
  } catch (err) {
    Sentry.captureException(err);
    await alertCritical('Backend failed to start', err as Error);
    fastify.log.error(err);
    process.exit(1);
  }
};

const shutdown = async (signal: string) => {
  console.log(`\n${signal} received, shutting down...`);
  await fastify.close();
  await prisma.$disconnect();
  process.exit(0);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', async (err) => {
  Sentry.captureException(err);
  await alertCritical('Uncaught exception', err);
});
process.on('unhandledRejection', async (reason) => {
  Sentry.captureException(reason as Error);
  await alertCritical('Unhandled rejection', reason as Error);
});

start();
