// src/routes/billing.ts — Pack 3: StoreKit 2 receipt validation
import { prisma } from '../config/db.js';
import { logAudit, AuditActions } from '../utils/audit.js';

const APP_STORE_SHARED_SECRET = process.env.APP_STORE_SHARED_SECRET;
const SANDBOX_VERIFY_URL = 'https://sandbox.itunes.apple.com/verifyReceipt';
const PROD_VERIFY_URL = 'https://buy.itunes.apple.com/verifyReceipt';

// Premium plans (matching StoreKit products in iOS)
const PLANS = {
  'plink.premium.monthly': { durationDays: 30, price: 199 },
  'plink.premium.yearly': { durationDays: 365, price: 1990 },
  'plink.premium.lifetime': { durationDays: 36500, price: 4990 },
};

export default async function billingRoutes(fastify) {

  // POST /api/billing/verify — verify Apple receipt and activate premium
  fastify.post('/billing/verify', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 5, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const { receipt, productId } = request.body;
    
    if (!receipt) {
      return reply.status(400).send({ error: 'Receipt required' });
    }
    if (!APP_STORE_SHARED_SECRET) {
      return reply.status(500).send({ error: 'APP_STORE_SHARED_SECRET not configured' });
    }
    if (!PLANS[productId]) {
      return reply.status(400).send({ error: 'Invalid productId' });
    }

    try {
      // Сначала пробуем production endpoint
      let response = await fetch(PROD_VERIFY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          'receipt-data': receipt,
          password: APP_STORE_SHARED_SECRET,
          'exclude-old-transactions': true,
        }),
      });
      let data: any = await response.json();

      // Apple: status 21007 = это sandbox receipt, надо перепроверить
      if (data.status === 21007) {
        response = await fetch(SANDBOX_VERIFY_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            'receipt-data': receipt,
            password: APP_STORE_SHARED_SECRET,
          }),
        });
        data = await response.json();
      }

      if (data.status !== 0) {
        await logAudit({
          userId: request.user.id,
          action: 'billing.verify_failed',
          ip: request.ip,
          metadata: { productId, status: data.status },
        });
        return reply.status(400).send({ 
          valid: false,
          error: `Receipt verification failed (status ${data.status})`,
        });
      }

      // Найдём нужную покупку в receipt
      const purchases = data.receipt?.in_app || [];
      const purchase = purchases.find((p: any) => p.product_id === productId);
      if (!purchase) {
        return reply.status(400).send({ valid: false, error: 'Purchase not found in receipt' });
      }

      // Проверим не истекла ли подписка
      const expiresMs = parseInt(purchase.expires_date_ms || '0');
      const now = Date.now();
      const plan = PLANS[productId as keyof typeof PLANS];
      
      let premiumUntil: Date;
      if (expiresMs > 0) {
        // Auto-renewable subscription
        premiumUntil = new Date(expiresMs);
        if (premiumUntil <= new Date()) {
          return reply.status(400).send({ valid: false, error: 'Subscription expired' });
        }
      } else {
        // Non-consumable (lifetime) or consumable
        premiumUntil = new Date(now + plan.durationDays * 24 * 3600 * 1000);
      }

      // Записываем подписку в БД
      await prisma.subscription.create({
        data: {
          userID: request.user.id,
          plan: productId,
          isActive: true,
          expiresAt: premiumUntil,
        },
      });

      // Активируем premium у юзера
      await prisma.user.update({
        where: { id: request.user.id },
        data: {
          isPremium: true,
          premiumUntil,
        },
      });

      await logAudit({
        userId: request.user.id,
        action: AuditActions.USER_PREMIUM_GRANTED,
        ip: request.ip,
        metadata: { productId, expiresAt: premiumUntil.toISOString() },
      });

      reply.send({
        valid: true,
        premium: true,
        premiumUntil: premiumUntil.toISOString(),
        plan: productId,
      });
    } catch (e: any) {
      console.error('Billing verify error', e);
      reply.status(500).send({ error: 'Verification failed: ' + e.message });
    }
  });

  // GET /api/billing/status — статус premium подписки
  fastify.get('/billing/status', {
    preHandler: [fastify.authenticate],
  }, async (request, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { isPremium: true, premiumUntil: true }
    });
    
    if (!user) return reply.status(404).send({ error: 'User not found' });

    const isActive = user.isPremium && 
                     (!user.premiumUntil || user.premiumUntil > new Date());

    reply.send({
      isPremium: isActive,
      premiumUntil: user.premiumUntil,
    });
  });

  // POST /api/billing/cancel — отменить подписку (mark inactive, не refund)
  fastify.post('/billing/cancel', {
    preHandler: [fastify.authenticate],
  }, async (request, reply) => {
    await prisma.subscription.updateMany({
      where: { 
        userID: request.user.id,
        isActive: true,
      },
      data: { isActive: false },
    });
    
    await logAudit({
      userId: request.user.id,
      action: 'billing.cancel',
      ip: request.ip,
    });
    
    reply.send({ success: true });
  });
}
