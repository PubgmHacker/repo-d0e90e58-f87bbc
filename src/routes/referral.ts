// src/routes/referral.ts — Pack 5: Referral program
import { prisma } from '../config/db.js';
import { logAudit } from '../utils/audit.js';
import crypto from 'crypto';

const REFERRAL_REWARD_DAYS = 7; // 7 дней premium за каждого приглашённого
const MAX_REFERRALS = 50; // максимум 50 * 7 = 350 дней premium

export default async function referralRoutes(fastify) {
  
  // GET /api/referral/code — получить реферальный код юзера
  fastify.get('/referral/code', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { id: true, referralCode: true }
    });
    
    if (!user) return reply.status(404).send({ error: 'User not found' });
    
    // Generate code if not exists
    let code = user.referralCode;
    if (!code) {
      code = generateReferralCode();
      await prisma.user.update({
        where: { id: user.id },
        data: { referralCode: code }
      });
    }
    
    reply.send({
      code,
      shareUrl: `https://plink-backend-production-ef31.up.railway.app/r/${code}`,
      reward: `${REFERRAL_REWARD_DAYS} days premium per friend`,
      maxReferrals: MAX_REFERRALS,
    });
  });
  
  // POST /api/referral/apply — применить реферальный код при регистрации
  fastify.post('/referral/apply', {
    config: { rateLimit: { max: 3, timeWindow: '1 hour' } }
  }, async (request, reply) => {
    const { code, userId } = request.body;
    
    if (!code || !userId) {
      return reply.status(400).send({ error: 'Code and userId required' });
    }
    
    // Найти реферера по коду
    const referrer = await prisma.user.findFirst({
      where: { referralCode: code.toUpperCase() }
    });
    
    if (!referrer) {
      return reply.status(404).send({ error: 'Invalid referral code' });
    }
    
    if (referrer.id === userId) {
      return reply.status(400).send({ error: 'Cannot use own referral code' });
    }
    
    // Проверить, не использовал ли юзер уже реферальный код
    const existing = await prisma.referral.findFirst({
      where: { referredId: userId }
    });
    
    if (existing) {
      return reply.status(400).send({ error: 'Referral code already used' });
    }
    
    // Проверить лимит рефералов
    const referrerCount = await prisma.referral.count({
      where: { referrerId: referrer.id, status: 'completed' }
    });
    
    if (referrerCount >= MAX_REFERRALS) {
      return reply.status(400).send({ error: 'Referrer has reached max referrals' });
    }
    
    // Создать реферальную запись
    await prisma.referral.create({
      data: {
        referrerId: referrer.id,
        referredId: userId,
        status: 'completed',
        rewardDays: REFERRAL_REWARD_DAYS,
      }
    });
    
    // Начислить premium обоим
    await grantPremium(referrer.id, REFERRAL_REWARD_DAYS);
    await grantPremium(userId, REFERRAL_REWARD_DAYS); // бонус новичку
    
    await logAudit({
      userId: referrer.id,
      action: 'referral.completed',
      metadata: { referredId: userId, rewardDays: REFERRAL_REWARD_DAYS }
    });
    
    reply.send({
      success: true,
      rewardDays: REFERRAL_REWARD_DAYS,
      message: `Both you and your friend got ${REFERRAL_REWARD_DAYS} days of premium!`,
    });
  });
  
  // GET /api/referral/stats — статистика рефералов
  fastify.get('/referral/stats', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const referrals = await prisma.referral.findMany({
      where: { referrerId: request.user.id },
      include: {
        referred: { select: { username: true, avatarURL: true, createdAt: true } }
      },
      orderBy: { createdAt: 'desc' }
    });
    
    const totalDays = referrals.reduce((sum, r) => sum + r.rewardDays, 0);
    
    reply.send({
      totalReferrals: referrals.length,
      totalDaysEarned: totalDays,
      maxReferrals: MAX_REFERRALS,
      remaining: MAX_REFERRALS - referrals.length,
      referrals: referrals.map(r => ({
        id: r.id,
        username: r.referred.username,
        avatarURL: r.referred.avatarURL,
        rewardDays: r.rewardDays,
        date: r.createdAt,
        status: r.status,
      })),
    });
  });
}

async function grantPremium(userId: string, days: number) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { premiumUntil: true, isPremium: true }
  });
  
  const now = new Date();
  const currentExpiry = user?.premiumUntil && user.premiumUntil > now 
    ? user.premiumUntil 
    : now;
  
  const newExpiry = new Date(currentExpiry.getTime() + days * 24 * 3600 * 1000);
  
  await prisma.user.update({
    where: { id: userId },
    data: {
      isPremium: true,
      premiumUntil: newExpiry,
    }
  });
  
  await prisma.subscription.create({
    data: {
      userID: userId,
      plan: 'referral',
      isActive: true,
      expiresAt: newExpiry,
    }
  });
}

function generateReferralCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // без I, O, 0, 1
  return Array.from({ length: 8 }, () => 
    chars[Math.floor(Math.random() * chars.length)]
  ).join('');
}
