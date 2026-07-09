// src/utils/tokens.ts — Pack 1.1: настраиваемый TTL через env
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { prisma } from '../config/db.js';
import { config } from '../config/index.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: number;
  refreshExpiresAt: number;
}

export async function issueTokenPair(fastify: any, userId: string, username?: string): Promise<TokenPair> {
  // Access token (по умолчанию 7 дней — не выкидывает из фильма)
  // 🔧 Pack v3: добавлен username в JWT — rooms.ts использует request.user.username
  const payload: any = { id: userId };
  if (username) payload.username = username;
  const accessToken = fastify.jwt.sign(
    payload,
    { expiresIn: config.ACCESS_TOKEN_TTL as any }
  );
  
  // Refresh token (по умолчанию 90 дней)
  const refreshPayload = crypto.randomBytes(48).toString('hex');
  const refreshHash = await bcrypt.hash(refreshPayload, 10);
  const refreshExpiresAt = new Date(
    Date.now() + config.REFRESH_TOKEN_TTL_DAYS * 24 * 3600 * 1000
  );
  
  await prisma.refreshToken.create({
    data: {
      userId,
      tokenHash: refreshHash,
      expiresAt: refreshExpiresAt,
    },
  });
  
  const refreshToken = `${userId}.${refreshPayload}`;
  
  // Вычисляем accessExpiresAt из TTL строки ('7d' → 7 * 24 * 3600 * 1000)
  const accessExpiresAt = parseTtlToMs(config.ACCESS_TOKEN_TTL);
  
  return {
    accessToken,
    refreshToken,
    accessExpiresAt: Date.now() + accessExpiresAt,
    refreshExpiresAt: refreshExpiresAt.getTime(),
  };
}

function parseTtlToMs(ttl: string): number {
  const match = ttl.match(/^(\d+)([smhd])$/);
  if (!match) return 7 * 24 * 3600 * 1000; // default 7 days
  const num = parseInt(match[1]);
  const unit = match[2];
  switch (unit) {
    case 's': return num * 1000;
    case 'm': return num * 60 * 1000;
    case 'h': return num * 3600 * 1000;
    case 'd': return num * 24 * 3600 * 1000;
    default: return 7 * 24 * 3600 * 1000;
  }
}

export async function verifyRefreshToken(fastify: any, refreshToken: string) {
  const [userId, payload] = refreshToken.split('.');
  if (!userId || !payload) return null;
  
  const tokens = await prisma.refreshToken.findMany({
    where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
  });
  
  for (const stored of tokens) {
    const match = await bcrypt.compare(payload, stored.tokenHash);
    if (match) {
      // Rotation: revoke this token
      await prisma.refreshToken.update({
        where: { id: stored.id },
        data: { revokedAt: new Date() },
      });
      return { userId, tokenId: stored.id };
    }
  }
  return null;
}

export async function revokeAllUserTokens(userId: string) {
  await prisma.refreshToken.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}
