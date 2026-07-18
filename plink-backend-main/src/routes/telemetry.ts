// src/routes/telemetry.ts — B3: Sync telemetry ingestion
// GPT-5.6 ADR-004: сырые samples в structured logs, агрегаты в Redis/DB.
import { prisma } from '../config/db.js';
import { logAudit } from '../utils/audit.js';

export default async function telemetryRoutes(fastify) {
  // POST /api/telemetry/sync-sample — приём одного sync sample от клиента
  fastify.post('/telemetry/sync-sample', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 120, timeWindow: '1 minute' } }  // 2s interval = 30/min
  }, async (request, reply) => {
    const sample = request.body;

    // Validate required fields
    if (!sample.sessionId || !sample.roomId || typeof sample.absoluteDriftMs !== 'number') {
      return reply.status(400).send({ error: 'sessionId, roomId, absoluteDriftMs required' });
    }

    // Structured log (not Prisma — GPT-5.6 ADR-004)
    request.log.info({
      type: 'sync_sample',
      userId: request.user.id,
      sessionId: sample.sessionId,
      roomId: sample.roomId,
      role: sample.role,
      absoluteDriftMs: sample.absoluteDriftMs,
      signedDriftMs: sample.signedDriftMs,
      correctionType: sample.correctionType,
      correctionMagnitude: sample.correctionMagnitude,
      playbackState: sample.playbackState,
      networkType: sample.networkType,
      provider: sample.provider,
      appBuild: sample.appBuild,
      timestamp: new Date().toISOString()
    }, 'sync_sample');

    // TODO: aggregate in Redis for session summary
    // For now, just acknowledge — logs are the source of truth

    reply.send({ received: true });
  });

  // POST /api/telemetry/sync-session — финальный session aggregate
  fastify.post('/telemetry/sync-session', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 hour' } }
  }, async (request, reply) => {
    const agg = request.body;

    if (!agg.sessionId || !agg.roomId) {
      return reply.status(400).send({ error: 'sessionId, roomId required' });
    }

    // Log aggregate
    request.log.info({
      type: 'sync_session_aggregate',
      userId: request.user.id,
      sessionId: agg.sessionId,
      roomId: agg.roomId,
      sampleCount: agg.sampleCount,
      medianDriftMs: agg.medianDriftMs,
      p95DriftMs: agg.p95DriftMs,
      maxDriftMs: agg.maxDriftMs,
      correctionCount: agg.correctionCount,
      reconnectDurations: agg.reconnectDurations,
      bufferingDurationMs: agg.bufferingDurationMs,
      provider: agg.provider,
      networkTypes: agg.networkTypes,
      appBuild: agg.appBuild,
      duration: agg.duration,
      timestamp: new Date().toISOString()
    }, 'sync_session_aggregate');

    reply.send({ received: true, sessionId: agg.sessionId });
  });
}
