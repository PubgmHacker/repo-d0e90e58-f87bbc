// src/routes/auth.ts — Pack 1.1: правильные rate limits
import bcrypt from 'bcryptjs';
import { prisma } from '../config/db.js';
import { issueTokenPair, verifyRefreshToken, revokeAllUserTokens } from '../utils/tokens.js';
import { logAudit, AuditActions } from '../utils/audit.js';
import { alertWarning } from '../utils/alerting.js';

export default async function authRoutes(fastify) {

  // POST /api/auth/signup — 5 регистраций за 20 минут
  fastify.post('/auth/signup', {
    config: {
      rateLimit: { max: 5, timeWindow: '20 minutes' }
    }
  }, async (request, reply) => {
    const { email, password, username } = request.body;
    if (!email || !password || !username) {
      return reply.status(400).send({ error: 'Missing fields' });
    }
    if (password.length < 6) {
      return reply.status(400).send({ error: 'Password must be at least 6 characters' });
    }

    const existing = await prisma.user.findFirst({
      where: { OR: [{ email }, { username }] }
    });
    if (existing) return reply.status(409).send({ error: 'Email or username taken' });

    const hashedPassword = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: { email, username, password: hashedPassword, isOnline: true }
    });

    const tokens = await issueTokenPair(fastify, user.id, user.username);
    
    await logAudit({
      userId: user.id,
      action: AuditActions.SIGNUP,
      ip: request.ip,
      userAgent: request.headers['user-agent'],
    });

    const { password: _, ...userWithoutPassword } = user;
    reply.send({
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      user: userWithoutPassword,
    });
  });

  // POST /api/auth/signin — 10 попыток входа за 5 минут
  fastify.post('/auth/signin', {
    config: {
      rateLimit: { max: 10, timeWindow: '5 minutes' }
    }
  }, async (request, reply) => {
    const { email, password } = request.body;
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      await logAudit({ action: AuditActions.LOGIN_FAILED, ip: request.ip, metadata: { email } });
      return reply.status(401).send({ error: 'Invalid credentials' });
    }

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) {
      await logAudit({ userId: user.id, action: AuditActions.LOGIN_FAILED, ip: request.ip });
      return reply.status(401).send({ error: 'Invalid credentials' });
    }

    if (user.bannedUntil && user.bannedUntil > new Date()) {
      return reply.status(403).send({ error: 'Account banned' });
    }

    await prisma.user.update({ where: { id: user.id }, data: { isOnline: true } });

    const tokens = await issueTokenPair(fastify, user.id, user.username);
    
    await logAudit({
      userId: user.id,
      action: AuditActions.LOGIN,
      ip: request.ip,
      userAgent: request.headers['user-agent'],
    });

    const { password: _, ...userWithoutPassword } = user;
    reply.send({
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      user: userWithoutPassword,
    });
  });

  // POST /api/auth/admin-verify — проверка админ-кода для конкретного email
  // 🔧 Pack v3: Специальный код ADM873IN7 для koslakandrej@gmail.com
  fastify.post('/auth/admin-verify', {
    config: { rateLimit: { max: 5, timeWindow: '10 minutes' } }
  }, async (request, reply) => {
    const { email, code } = request.body;
    if (!email || !code) {
      return reply.status(400).send({ error: 'Email and code required' });
    }

    // Проверка кода
    const ADMIN_EMAIL = 'koslakandrej@gmail.com';
    const ADMIN_CODE = 'ADM873IN7';

    if (email.toLowerCase() !== ADMIN_EMAIL) {
      return reply.status(403).send({ error: 'Not eligible for admin verification' });
    }
    if (code !== ADMIN_CODE) {
      return reply.status(401).send({ error: 'Invalid admin code' });
    }

    // Назначить роль ADMIN
    const user = await prisma.user.findUnique({ where: { email: ADMIN_EMAIL } });
    if (!user) return reply.status(404).send({ error: 'User not found' });

    await prisma.user.update({
      where: { id: user.id },
      data: { role: 'ADMIN', isPremium: true }
    });

    await logAudit({
      userId: user.id,
      action: 'admin.verified',
      ip: request.ip,
    });

    // Выдать новые токены с admin ролью
    const tokens = await issueTokenPair(fastify, user.id, user.username);

    const { password: _, ...userWithoutPassword } = user;
    reply.send({
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      user: { ...userWithoutPassword, role: 'ADMIN', isPremium: true },
    });
  });

  // POST /api/auth/refresh — 60 в минуту (часто, т.к. каждый запуск приложения)
  fastify.post('/auth/refresh', {
    config: {
      rateLimit: { max: 60, timeWindow: '1 minute' }
    }
  }, async (request, reply) => {
    const { refreshToken } = request.body;
    if (!refreshToken) {
      return reply.status(400).send({ error: 'Refresh token required' });
    }

    const verified = await verifyRefreshToken(fastify, refreshToken);
    if (!verified) {
      await alertWarning('Invalid refresh token attempt');
      return reply.status(401).send({ error: 'Invalid or expired refresh token' });
    }

    const user = await prisma.user.findUnique({
      where: { id: verified.userId },
      select: { id: true, username: true, email: true, role: true, isPremium: true, bannedUntil: true }
    });
    if (!user) return reply.status(401).send({ error: 'User not found' });
    if (user.bannedUntil && user.bannedUntil > new Date()) {
      return reply.status(403).send({ error: 'Account banned' });
    }

    const tokens = await issueTokenPair(fastify, user.id, user.username);
    
    await logAudit({
      userId: user.id,
      action: AuditActions.TOKEN_REFRESH,
      ip: request.ip,
    });

    reply.send({
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      user,
    });
  });

  // POST /api/auth/logout
  fastify.post('/auth/logout', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    await revokeAllUserTokens(request.user.id);
    await prisma.user.update({
      where: { id: request.user.id },
      data: { isOnline: false }
    });
    
    await logAudit({
      userId: request.user.id,
      action: AuditActions.LOGOUT,
      ip: request.ip,
    });
    
    reply.send({ success: true });
  });

  // POST /api/auth/fcm-token
  fastify.post('/auth/fcm-token', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const { token: fcmToken } = request.body;
    await prisma.user.update({
      where: { id: request.user.id },
      data: { fcmToken }
    });
    reply.send({ success: true });
  });
}
