// src/index.ts — Pack 6: добавлена регистрация AI routes
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
import { securityHeaders } from './middleware/security.js';
// LEGACY: this file is preserved for v1 rollback per runbook §0.
// It is NOT imported by src/app.ts or src/server.ts in v2 builds.
// The import path below points at the renamed legacy ws-handler.
import { setupWebSocketHandler } from './websocket/legacy-ws-handler.js';
import { register } from './services/metrics.js';
import { initTelemetry } from './services/telemetry.js';
import authRoutes from './routes/auth.js';
import roomRoutes from './routes/rooms.js';
import friendRoutes from './routes/friends.js';
import messageRoutes from './routes/messages.js';
import profileRoutes from './routes/profile.js';
import mediaRoutes from './routes/media.js';
import billingRoutes from './routes/billing.js';
import gdprRoutes from './routes/gdpr.js';
import featureFlagRoutes from './routes/featureFlags.js';
import aiRoutes from './routes/ai.js';  // ← Pack 6
import { alertCritical } from './utils/alerting.js';
import { pipeline } from 'node:stream';
import { Readable } from 'node:stream';

initTelemetry(process.env.OTEL_ENDPOINT);

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
    redact: ['req.headers.authorization', 'req.body.password', '*.password', 'req.body.receipt'],
  },
});

fastify.decorate('prisma', prisma);

await fastify.register(cors, { 
  origin: config.CORS_ORIGIN, 
  credentials: true,
  methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'X-Request-ID'],
});
await fastify.register(jwt, { 
  secret: config.JWT_SECRET,
  sign: { algorithm: 'HS256', iss: 'plink', aud: 'plink-ios' },
});
await fastify.register(rateLimit, {
  global: false,
  max: 100,
  timeWindow: '1 minute',
  cache: 10000,
  ban: 5,
});
await fastify.register(websocket, { options: { maxPayload: 1048576 } });

fastify.decorate('authenticate', authenticate);
fastify.addHook('onRequest', securityHeaders);

// ═══════════════════════════════════════════════════════════════════════════
// v100: Authenticated Server-Side Extraction (StreamRelay)
// ═══════════════════════════════════════════════════════════════════════════
// PROBLEM (v97-v99):
//   - v97 transparent-proxy: strips `ip` from URL → breaks signature → 403
//   - v99 IOS innertube from WebView: sync XHR blocked, fell through to MP4
//   - yt-dlp on Railway: blocked (429 / Precondition Failed) regardless of cookies
//
// SOLUTION (v100): Server does the IOS innertube API call ITSELF.
//   1. iOS sends: videoId + b64cookies + b64ua (just identity, no extracted URL)
//   2. Backend POSTs to https://www.youtube.com/youtubei/v1/player with:
//        - clientName: 'IOS' (returns hlsManifestUrl, NOT IP-bound)
//        - iPhone cookies (VISITOR_INFO1_LIVE, YSC, etc.)
//        - iPhone User-Agent (matches the iPhone that "owns" the cookies)
//        - SAPISIDHASH Authorization header (computed from SAPISID cookie)
//   3. YouTube generates URL bound to BACKEND IP (since backend made the request)
//   4. Backend immediately fetches that URL from the SAME IP → IP matches → 200 OK
//   5. Backend pipes bytes to AVPlayer
//
// Why this works where v95/v96 yt-dlp failed:
//   - yt-dlp triggers YouTube's bot detection (it's a known scraper tool)
//   - /youtubei/v1/player is just a JSON HTTP API — no bot detection
//   - With iPhone cookies, YouTube sees the request as the iPhone user
//   - HLS manifest URLs (hlsManifestUrl) are NOT IP-bound (sparams lacks `ip`)
//     → even if AVPlayer somehow fetched directly, would still work
//   - But more importantly: extraction-IP == streaming-IP (both = backend)
//
// Mode priority:
//   - videoId + cookies + UA (v100 authenticated server extract) ← PRIMARY
//   - b64url (v97 transparent proxy) ← fallback (will 403, kept for safety)
//   - url (legacy) ← last resort
// ═══════════════════════════════════════════════════════════════════════════
const PIPED_INSTANCES = [
  'https://pipedapi.kavin.rocks',
  'https://pipedapi.leptons.xyz',
  'https://pipedapi.r4fo.com',
];

/**
 * v100: Build SAPISIDHASH header from SAPISID cookie.
 * YouTube requires this header for authenticated innertube API calls.
 * Format: SAPISIDHASH = <unix_timestamp>_<SHA1(SAPISID + " " + origin + " " + timestamp)>
 */
function buildSapisidHash(cookieHeader: string, origin: string): string | null {
  const match = cookieHeader.match(/SAPISID=([^;]+)/);
  if (!match) return null;
  const sapisid = match[1];
  const ts = Math.floor(Date.now() / 1000);
  // Use Node.js crypto module
  const crypto = require('crypto');
  const hash = crypto.createHash('sha1')
    .update(`${sapisid} ${origin} ${ts}`)
    .digest('hex');
  return `SAPISIDHASH ${ts}_${hash}`;
}

/**
 * v100: Authenticated IOS innertube API extraction.
 *
 * POSTs to /youtubei/v1/player with iPhone cookies + UA + SAPISIDHASH.
 * YouTube returns streamingData with hlsManifestUrl (preferred) or formats[].
 *
 * The URL YouTube generates is bound to BACKEND IP (since backend made the
 * request). Backend then fetches that URL from the same IP → IP matches → 200.
 */
async function extractStreamURLAuthenticated(
  videoId: string,
  cookieHeader: string,
  userAgent: string
): Promise<string> {
  console.log('[Extract-v100] Authenticated IOS innertube extraction for', videoId);
  console.log('[Extract-v100] Cookies length:', cookieHeader.length, 'UA length:', userAgent.length);

  // SAPISIDHASH for authenticated request (uses SAPISID cookie if present)
  const origin = 'https://www.youtube.com';
  const authHash = buildSapisidHash(cookieHeader, origin);

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': origin + '/',
    'X-YouTube-Client-Name': '5',      // 5 = IOS client
    'X-YouTube-Client-Version': '17.31.4',
    'Accept-Language': 'en-US,en;q=0.9',
  };
  if (cookieHeader) {
    headers['Cookie'] = cookieHeader;
  }
  if (authHash) {
    headers['Authorization'] = authHash;
    console.log('[Extract-v100] ✅ Built SAPISIDHASH authorization header');
  } else {
    console.log('[Extract-v100] ⚠️ No SAPISID cookie found — request will be unauthenticated');
  }

  const body = JSON.stringify({
    context: {
      client: {
        clientName: 'IOS',
        clientVersion: '17.31.4',
        hl: 'en',
        gl: 'US'
      }
    },
    videoId: videoId,
    playbackContext: {
      contentPlaybackContext: {
        html5Preference: 'HTML5_PREF_WANTS',
        signatureTimestamp: 20075  // recent STS, YouTube accepts a wide range
      }
    }
  });

  const url = 'https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8&prettyPrint=false';
  console.log('[Extract-v100] POST', url.substring(0, 80) + '...');

  const res = await fetch(url, {
    method: 'POST',
    headers,
    body,
    signal: AbortSignal.timeout(15000),
  });

  console.log('[Extract-v100] Response status:', res.status);

  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    throw new Error(`innertube ${res.status}: ${errText.substring(0, 200)}`);
  }

  const data: any = await res.json();
  const sd = data?.streamingData;
  if (!sd) {
    throw new Error('innertube: no streamingData in response. playabilityStatus=' +
      JSON.stringify(data?.playabilityStatus)?.substring(0, 200));
  }

  // Priority 1: HLS manifest (NOT IP-bound, works through proxy AND direct)
  if (sd.hlsManifestUrl) {
    console.log('[Extract-v100] ✅ Got hlsManifestUrl (NOT IP-bound)');
    return sd.hlsManifestUrl;
  }

  // Priority 2: muxed MP4 (IP-bound to backend — backend fetches it, so OK)
  const formats = sd.formats || [];
  const best = formats.find((f: any) => f.itag === 22)
            || formats.find((f: any) => f.itag === 18)
            || formats[0];
  if (best && best.url) {
    console.log('[Extract-v100] ✅ Got MP4 itag:', best.itag, '(IP-bound to backend, will fetch directly)');
    return best.url;
  }

  throw new Error('innertube: no hlsManifestUrl and no formats in streamingData');
}

async function extractStreamURL(videoId: string): Promise<string> {
  // Try Piped API first (fastest)
  for (const instance of PIPED_INSTANCES) {
    try {
      console.log('[Extract] Trying Piped:', instance);
      const res = await fetch(`${instance}/streams/${videoId}`, {
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) continue;
      const data: any = await res.json();

      // Priority 1: muxed MP4 (itag 22=720p, 18=360p)
      if (data.videoStreams && Array.isArray(data.videoStreams)) {
        const muxed = data.videoStreams.filter((s: any) => !s.videoOnly);
        const best = muxed.find((s: any) => s.itag === 22)
                   || muxed.find((s: any) => s.itag === 18)
                   || muxed[0];
        if (best && best.url) {
          console.log('[Extract] ✅ Piped muxed MP4 itag:', best.itag);
          return best.url;
        }
      }

      // Priority 2: HLS
      if (data.hls) {
        console.log('[Extract] ✅ Piped HLS');
        return data.hls;
      }
    } catch (e: any) {
      console.log('[Extract] Piped failed:', e.message);
    }
  }

  // Fallback: yt-dlp (if available on Railway)
  try {
    console.log('[Extract] Trying yt-dlp...');
    const { execSync } = await import('child_process');
    const output = execSync(
      `yt-dlp -f "best[ext=mp4][vcodec!=none][acodec!=none]/best[vcodec!=none][acodec!=none]" -g "https://www.youtube.com/watch?v=${videoId}"`,
      { timeout: 15000, encoding: 'utf-8' }
    ).trim();
    if (output && output.includes('http')) {
      console.log('[Extract] ✅ yt-dlp URL:', output.substring(0, 80));
      return output;
    }
  } catch (e: any) {
    console.log('[Extract] yt-dlp failed:', e.message?.substring(0, 100));
  }

  throw new Error('All extraction methods failed');
}

// Cache for extracted URLs (5 min TTL — googlevideo URLs live ~6h)
const urlCache = new Map<string, { url: string; expires: number }>();

fastify.get('/api/media/stream', {
  config: { rateLimit: { max: 60, timeWindow: '1 minute' } }
}, async (request: any, reply: any) => {
  console.log('[Relay] ====== StreamRelay request received ======');

  // Override security headers for AVPlayer
  reply.header('Cross-Origin-Resource-Policy', 'cross-origin');
  reply.header('Cross-Origin-Embedder-Policy', 'unsafe-none');
  reply.header('Access-Control-Allow-Origin', '*');
  reply.header('Access-Control-Allow-Headers', 'Range, Content-Type');
  reply.header('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');

  // Parse raw query string
  const rawQuery = request.url.split('?')[1] || '';
  const videoIdParam = new URLSearchParams(rawQuery).get('videoId');
  const b64urlParam = new URLSearchParams(rawQuery).get('b64url');
  const urlParam = new URLSearchParams(rawQuery).get('url');
  const tokenParam = new URLSearchParams(rawQuery).get('token');
  const b64cookiesParam = new URLSearchParams(rawQuery).get('b64cookies');
  const b64uaParam = new URLSearchParams(rawQuery).get('b64ua'); // v97: WebView UA

  console.log('[Relay] videoId:', videoIdParam || 'none', 'b64url:', !!b64urlParam, 'b64cookies:', !!b64cookiesParam, 'b64ua:', !!b64uaParam);

  if (!tokenParam) return reply.status(401).send({ error: 'Token required' });
  try {
    fastify.jwt.verify(tokenParam);
  } catch {
    return reply.status(401).send({ error: 'Invalid token' });
  }

  // v96: Decode cookies from base64 (sent by iOS ExtractionBridge)
  let cookieHeader = '';
  if (b64cookiesParam) {
    try {
      cookieHeader = Buffer.from(b64cookiesParam, 'base64').toString('utf-8');
      console.log('[Relay] ✅ Decoded cookies, length:', cookieHeader.length);
    } catch {
      console.log('[Relay] ⚠️ Failed to decode cookies');
    }
  }

  // v97: Decode User-Agent from base64 (sent by iOS — the UA that the WebView
  // used to extract the stream URL). Forwarding the SAME UA to YouTube CDN
  // is critical: YouTube validates UA consistency between page-load (extraction)
  // and media-fetch. If we sent a desktop UA here, YouTube would 403.
  let userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) ' +
                  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 ' +
                  'Mobile/15E148 Safari/604.1';
  if (b64uaParam) {
    try {
      userAgent = Buffer.from(b64uaParam, 'base64').toString('utf-8');
      console.log('[Relay] ✅ Decoded User-Agent, len:', userAgent.length);
    } catch {
      console.log('[Relay] ⚠️ Failed to decode User-Agent, using default iPhone UA');
    }
  }

  // Determine target URL
  let targetUrl: string | null = null;

  // ═══════════════════════════════════════════════════════════════════════
  // Mode 1 (PRIMARY, v100): videoId + cookies + UA — Authenticated Server Extract
  // ═══════════════════════════════════════════════════════════════════════
  // Backend POSTs to /youtubei/v1/player with IOS client + iPhone cookies + UA.
  // YouTube returns URL bound to BACKEND IP. Backend fetches it (same IP) → 200.
  // This is the WORKING path — extraction-IP == streaming-IP.
  if (videoIdParam) {
    const cached = urlCache.get(videoIdParam);
    if (cached && cached.expires > Date.now()) {
      targetUrl = cached.url;
      console.log('[Relay] ✅ Using cached URL for videoId:', videoIdParam);
    } else {
      try {
        console.log('[Relay] v100: authenticated extraction for videoId:', videoIdParam);
        // v100: try authenticated IOS innertube FIRST (works with iPhone cookies)
        try {
          targetUrl = await extractStreamURLAuthenticated(videoIdParam, cookieHeader, userAgent);
          urlCache.set(videoIdParam, { url: targetUrl, expires: Date.now() + 300000 });
          console.log('[Relay] ✅ v100 authenticated extraction succeeded + cached');
        } catch (authErr: any) {
          // v100 fallback: legacy yt-dlp/Piped extraction (likely fails on Railway)
          console.warn('[Relay] ⚠️ v100 authenticated failed:', authErr.message);
          console.log('[Relay] Falling back to legacy extractStreamURL (yt-dlp/Piped)...');
          targetUrl = await extractStreamURL(videoIdParam);
          urlCache.set(videoIdParam, { url: targetUrl, expires: Date.now() + 300000 });
          console.log('[Relay] ✅ Legacy extraction succeeded + cached');
        }
      } catch (e: any) {
        console.error('[Relay] ❌ All extraction methods failed:', e.message);
        return reply.status(502).send({ error: 'Extraction failed: ' + e.message });
      }
    }
  }
  // ═══════════════════════════════════════════════════════════════════════
  // Mode 2 (FALLBACK, v97): b64url — Transparent Proxy.
  // ═══════════════════════════════════════════════════════════════════════
  // iOS extracted the googlevideo URL; backend strips `ip` and forwards with
  // iPhone UA + cookies. KNOWN BROKEN: stripping `ip` breaks signature → 403.
  // Kept as fallback for cases where iOS has URL but no videoId.
  else if (b64urlParam) {
    try {
      const decoded = Buffer.from(b64urlParam, 'base64').toString('utf-8');

      // Strip the `ip` query parameter (v97 logic — known to break signature)
      let cleaned = decoded.replace(/&amp;/g, '&');
      cleaned = cleaned.replace(/[&?]ip=[^&]+/g, '');
      if (!cleaned.includes('?')) {
        const firstAmp = cleaned.indexOf('&');
        if (firstAmp !== -1) {
          cleaned = cleaned.substring(0, firstAmp) + '?' + cleaned.substring(firstAmp + 1);
        }
      }
      cleaned = cleaned.replace(/&&/g, '&').replace(/[?&]$/, '');

      targetUrl = cleaned;
      console.log('[Relay] ⚠️ v97 transparent-proxy fallback (will likely 403): decoded + stripped `ip`');
      console.log('[Relay] Before:', decoded.substring(0, 160));
      console.log('[Relay] After: ', cleaned.substring(0, 160));
    } catch {
      return reply.status(400).send({ error: 'Invalid base64' });
    }
  }
  // Mode 3 (LEGACY): raw url — pass-through without modification.
  else if (urlParam) {
    targetUrl = urlParam;
  } else {
    return reply.status(400).send({ error: 'videoId, b64url, or url required' });
  }

  if (!targetUrl) {
    return reply.status(500).send({ error: 'No stream URL' });
  }

  console.log('[Relay] Target:', targetUrl.substring(0, 100) + '...');

  try {
    // v97: Forward iPhone UA (from iOS WebView) + cookies + Referer to YouTube CDN.
    // This makes the backend look like the iPhone itself — YouTube can't
    // distinguish the proxy request from the original extraction request.
    const upstreamHeaders: Record<string, string> = {
      'User-Agent': userAgent,
      'Referer': 'https://www.youtube.com/',
      'Origin': 'https://www.youtube.com',
    };
    // v96: Add cookies from client (Authenticated Proxy)
    if (cookieHeader) {
      upstreamHeaders['Cookie'] = cookieHeader;
      console.log('[Relay] ✅ Sending cookies to YouTube CDN');
    }
    if (request.headers.range) upstreamHeaders['Range'] = request.headers.range;

    console.log('[Relay] Fetching from YouTube CDN with iPhone UA + cookies...');
    const upstreamRes = await fetch(targetUrl, { headers: upstreamHeaders, redirect: 'follow' });

    console.log('[Relay] Upstream status:', upstreamRes.status, 'Content-Length:', upstreamRes.headers.get('content-length'));

    if (!upstreamRes.ok && upstreamRes.status !== 206) {
      const errorBody = await upstreamRes.text().catch(() => 'unreadable');
      console.error('[Relay] ❌ Upstream error:', upstreamRes.status, errorBody.substring(0, 200));
      // If 403, invalidate cache (URL may be expired/IP-bound)
      if (upstreamRes.status === 403 && videoIdParam) {
        urlCache.delete(videoIdParam);
        console.log('[Relay] Cache invalidated for videoId:', videoIdParam);
      }
      return reply.status(upstreamRes.status).send({ error: `YouTube ${upstreamRes.status}` });
    }

    if (upstreamRes.body) {
      const nodeStream = Readable.fromWeb(upstreamRes.body);
      reply.hijack();
      const raw = reply.raw;
      const respHeaders: Record<string, string> = {
        'Content-Type': upstreamRes.headers.get('content-type') || 'video/mp4',
        'Accept-Ranges': 'bytes',
      };
      const cl = upstreamRes.headers.get('content-length');
      if (cl) respHeaders['Content-Length'] = cl;
      const cr = upstreamRes.headers.get('content-range');
      if (cr) respHeaders['Content-Range'] = cr;
      raw.writeHead(upstreamRes.status, respHeaders);

      pipeline(nodeStream, raw, (err: any) => {
        if (err) {
          console.error('[Relay] ❌ Pipeline error:', err.message);
          if (!raw.destroyed) raw.destroy();
        } else {
          console.log('[Relay] ✅ Pipeline complete');
        }
      });
      return;
    } else {
      return reply.send(Buffer.alloc(0));
    }
  } catch (e: any) {
    console.error('[Relay] ❌ Error:', e.message);
    return reply.status(502).send({ error: 'Stream relay failed: ' + e.message });
  }
});

// 404 RADAR
fastify.setNotFoundHandler((request: any, reply: any) => {
  console.log(`[404 RADAR] Missed: ${request.method} ${request.url.substring(0, 200)}`);
  reply.code(404).send({ error: 'Not Found' });
});

await fastify.register(authRoutes, { prefix: '/api' });
await fastify.register(roomRoutes, { prefix: '/api' });
await fastify.register(friendRoutes, { prefix: '/api' });
await fastify.register(messageRoutes, { prefix: '/api' });
await fastify.register(profileRoutes, { prefix: '/api' });
await fastify.register(mediaRoutes, { prefix: '/api' });
await fastify.register(billingRoutes, { prefix: '/api' });
await fastify.register(gdprRoutes, { prefix: '/api' });
await fastify.register(featureFlagRoutes, { prefix: '/api' });
await fastify.register(aiRoutes, { prefix: '/api' });  // ← Pack 6

setupWebSocketHandler(fastify.websocketServer, prisma, fastify);

// 🔧 FIX: Register /ws and /ws/room/:id as Fastify websocket routes.
// Without this, Fastify returns 404 for the HTTP upgrade request and
// iOS WS client can't connect → RoomView hangs on "loading" forever.
// @fastify/websocket plugin auto-routes upgrade requests to these handlers.
// The actual connection logic is in setupWebSocketHandler (raw 'connection'
// event on fastify.websocketServer). These route handlers are no-ops —
// they exist only so Fastify allows the WebSocket upgrade.
fastify.get('/ws', { websocket: true }, async () => {});
fastify.get('/ws/room/:id', { websocket: true }, async () => {});

fastify.get('/health', async () => {
  const db = await checkDatabase();
  const redis = await checkRedis();
  return {
    status: db ? 'ok' : 'degraded',
    timestamp: Date.now(),
    uptime: process.uptime(),
    version: '1.6.1-v10.2',
    environment: config.NODE_ENV,
    services: {
      database: db ? 'up' : 'down',
      redis: redis ? 'up' : (config.REDIS_URL ? 'down' : 'not_configured'),
      yt_dlp: 'available',
      sentry: config.SENTRY_DSN ? 'configured' : 'not_configured',
      ai: process.env.OPENROUTER_API_KEY ? 'configured' : 'not_configured',
    },
    memory: process.memoryUsage(),
  };
});

fastify.get('/metrics', async (req, reply) => {
  reply.type('text/plain').send(await register.metrics());
});

async function checkDatabase(): Promise<boolean> {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}

fastify.setErrorHandler((error: any, request: any, reply: any) => {
  if (error.statusCode >= 500) {
    Sentry.captureException(error);
    alertCritical('Server error', error as Error);
  }
  reply.status(error.statusCode || 500).send({
    error: error.message || 'Internal Server Error',
    statusCode: error.statusCode || 500,
    requestId: request.id,
  });
});

const start = async () => {
  try {
    await fastify.listen({ port: config.PORT, host: '0.0.0.0' });
    console.log(`🚀 Plink backend v1.6.0 on port ${config.PORT} [${config.NODE_ENV}]`);
    console.log(`🤖 AI: /api/ai/chat | /api/ai/recommend`);

    // v94.14: Рентген роутов — выводим все зарегистрированные пути
    await fastify.ready();
    console.log('📋 REGISTERED ROUTES:');
    console.log(fastify.printRoutes());
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
