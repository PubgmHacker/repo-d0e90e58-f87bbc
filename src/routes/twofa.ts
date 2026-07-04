// src/routes/twofa.ts — Pack 4: 2FA setup + verify endpoints
import { prisma } from '../config/db.js';
import {
  generateTOTPSecret,
  generateOTPAuthURL,
  verifyTOTP,
  generateBackupCodes,
  validatePasswordStrength,
} from '../middleware/security.js';
import { logAudit } from '../utils/audit.js';
import { issueTokenPair } from '../utils/tokens.js';
import bcrypt from 'bcryptjs';

export default async function twofaRoutes(fastify) {
  
  // POST /api/2fa/setup
  fastify.post('/2fa/setup', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { id: true, email: true, twofaSecret: true, twofaEnabled: true }
    });
    
    if (!user) return reply.status(404).send({ error: 'User not found' });
    if (user.twofaEnabled) return reply.status(400).send({ error: '2FA already enabled' });
    
    const secret = user.twofaSecret || generateTOTPSecret();
    const otpauthUrl = generateOTPAuthURL(secret, user.email);
    
    await prisma.user.update({
      where: { id: user.id },
      data: { twofaSecret: secret }
    });
    
    reply.send({
      secret,
      otpauthUrl,
      qrCodeUrl: `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(otpauthUrl)}`,
    });
  });
  
  // POST /api/2fa/verify
  fastify.post('/2fa/verify', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const { code } = request.body;
    if (!code) return reply.status(400).send({ error: 'Code required' });
    
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { id: true, twofaSecret: true, twofaEnabled: true }
    });
    
    if (!user) return reply.status(404).send({ error: 'User not found' });
    if (user.twofaEnabled) return reply.status(400).send({ error: '2FA already enabled' });
    if (!user.twofaSecret) return reply.status(400).send({ error: 'Setup 2FA first' });
    
    if (!verifyTOTP(user.twofaSecret, code)) {
      return reply.status(401).send({ error: 'Invalid code' });
    }
    
    const backupCodes = generateBackupCodes();
    await prisma.user.update({
      where: { id: user.id },
      data: {
        twofaEnabled: true,
        twofaBackupCodes: JSON.stringify(backupCodes),
      }
    });
    
    await logAudit({ userId: user.id, action: '2fa.enabled', ip: request.ip });
    
    reply.send({
      enabled: true,
      backupCodes,
      warning: 'Сохраните backup codes в надёжном месте',
    });
  });
  
  // POST /api/2fa/disable
  fastify.post('/2fa/disable', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const { password, code } = request.body;
    
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { id: true, password: true, twofaSecret: true, twofaEnabled: true }
    });
    
    if (!user) return reply.status(404).send({ error: 'User not found' });
    if (!user.twofaEnabled) return reply.status(400).send({ error: '2FA not enabled' });
    
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) return reply.status(401).send({ error: 'Invalid password' });
    
    if (!verifyTOTP(user.twofaSecret!, code)) {
      return reply.status(401).send({ error: 'Invalid 2FA code' });
    }
    
    await prisma.user.update({
      where: { id: user.id },
      data: {
        twofaEnabled: false,
        twofaSecret: null,
        twofaBackupCodes: null,
      }
    });
    
    await logAudit({ userId: user.id, action: '2fa.disabled', ip: request.ip });
    reply.send({ disabled: true });
  });
  
  // POST /api/2fa/verify-login — проверка 2FA при логине
  fastify.post('/2fa/verify-login', {
    config: { rateLimit: { max: 5, timeWindow: '5 minutes' } }
  }, async (request, reply) => {
    const { tempToken, code } = request.body;
    
    try {
      const payload = fastify.jwt.verify(tempToken) as any;
      const user = await prisma.user.findUnique({
        where: { id: payload.userId },
        select: { id: true, twofaSecret: true, twofaBackupCodes: true }
      });
      
      if (!user || !user.twofaSecret) {
        return reply.status(400).send({ error: '2FA not set up' });
      }
      
      if (verifyTOTP(user.twofaSecret, code)) {
        const tokens = await issueTokenPair(fastify, user.id);
        return reply.send(tokens);
      }
      
      const backupCodes: string[] = JSON.parse(user.twofaBackupCodes || '[]');
      const idx = backupCodes.indexOf(code.toUpperCase());
      if (idx >= 0) {
        backupCodes.splice(idx, 1);
        await prisma.user.update({
          where: { id: user.id },
          data: { twofaBackupCodes: JSON.stringify(backupCodes) }
        });
        const tokens = await issueTokenPair(fastify, user.id);
        return reply.send(tokens);
      }
      
      return reply.status(401).send({ error: 'Invalid code' });
    } catch {
      return reply.status(401).send({ error: 'Invalid or expired temp token' });
    }
  });
  
  // GET /api/2fa/status
  fastify.get('/2fa/status', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { twofaEnabled: true }
    });
    reply.send({ enabled: user?.twofaEnabled || false });
  });
  
  // POST /api/password/strength
  fastify.post('/password/strength', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const { password } = request.body;
    const result = validatePasswordStrength(password);
    reply.send(result);
  });
}
