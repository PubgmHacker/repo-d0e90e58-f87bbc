// src/routes/legacy/legacyStreamRelay.ts — LEGACY YouTube extraction relay
//
// ⛔ SOFT-RETIRED (2026-07-16 MVP): keep file for one release cycle; do not
// extend. Default APP_STORE_COMPLIANT build never registers these routes.
// Scheduled for hard delete after App Store approval cycle.
//
// ⚠️ FORBIDDEN in App Store compliant builds (runbook §7).
//
// This file contains the exact logic that was previously inlined in
// src/index.ts (v100 — authenticated server-side IOS innertube extraction).
// It is preserved ONLY behind feature flags so the v1→v2 rollout can fall
// back if needed:
//
//   APP_STORE_COMPLIANT=true     → routes never registered (default)
//   ENABLE_LEGACY_STREAM_RELAY=false → routes never registered (default)
//
// To enable: APP_STORE_COMPLIANT=false AND ENABLE_LEGACY_STREAM_RELAY=true.
// This combination is allowed ONLY in internal/staging builds. Production
// must keep both flags at their safe defaults.
//
// Known defects of this flow (runbook §7):
//   - Violates YouTube ToS (server-side extraction with user cookies)
//   - Violates Apple App Store Review Guideline 5.6 (content extraction)
//   - Sends user YouTube cookies to the backend (§19 violation)
//   - Raw CDN proxy through /api/media/stream (forbidden)
//   - execSync('yt-dlp ...') on the request path (§19: 'execSync запрещен
//     на request path. Вынести legacy worker в очередь или удалить.')
//
// All of these are why this code is gated behind feature flags and will
// be deleted after one release cycle per runbook §15.

import type { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { config } from '../../config/index.js';

const PIPED_INSTANCES = [
  'https://pipedapi.kavin.rocks',
  'https://pipedapi.leptons.xyz',
  'https://pipedapi.r4fo.com',
];

function buildSapisidHash(cookieHeader: string, origin: string): string | null {
  const match = cookieHeader.match(/SAPISID=([^;]+)/);
  if (!match) return null;
  const sapisid = match[1];
  const ts = Math.floor(Date.now() / 1000);
  const hash = createHash('sha1')
    .update(`${sapisid} ${origin} ${ts}`)
    .digest('hex');
  return `SAPISIDHASH ${ts}_${hash}`;
}

async function extractStreamURLAuthenticated(
  videoId: string,
  cookieHeader: string,
  userAgent: string,
): Promise<string> {
  const origin = 'https://www.youtube.com';
  const authHash = buildSapisidHash(cookieHeader, origin);

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': origin + '/',
    'X-YouTube-Client-Name': '5',
    'X-YouTube-Client-Version': '17.31.4',
    'Accept-Language': 'en-US,en;q=0.9',
  };
  if (cookieHeader) headers['Cookie'] = cookieHeader;
  if (authHash) headers['Authorization'] = authHash;

  const body = JSON.stringify({
    context: { client: { clientName: 'IOS', clientVersion: '17.31.4', hl: 'en', gl: 'US' } },
    videoId,
    playbackContext: {
      contentPlaybackContext: { html5Preference: 'HTML5_PREF_WANTS', signatureTimestamp: 20075 },
    },
  });

  const url =
    'https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8&prettyPrint=false';
  const res = await fetch(url, {
    method: 'POST',
    headers,
    body,
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    throw new Error(`innertube ${res.status}: ${errText.substring(0, 200)}`);
  }
  const data: any = await res.json();
  const sd = data?.streamingData;
  if (!sd) {
    throw new Error(
      'innertube: no streamingData. playabilityStatus=' +
        JSON.stringify(data?.playabilityStatus)?.substring(0, 200),
    );
  }
  if (sd.hlsManifestUrl) return sd.hlsManifestUrl;
  const formats = sd.formats || [];
  const best =
    formats.find((f: any) => f.itag === 22) ||
    formats.find((f: any) => f.itag === 18) ||
    formats[0];
  if (best?.url) return best.url;
  throw new Error('innertube: no hlsManifestUrl and no formats');
}

async function extractStreamURL(videoId: string): Promise<string> {
  for (const instance of PIPED_INSTANCES) {
    try {
      const res = await fetch(`${instance}/streams/${videoId}`, {
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) continue;
      const data: any = await res.json();
      if (Array.isArray(data.videoStreams)) {
        const muxed = data.videoStreams.filter((s: any) => !s.videoOnly);
        const best =
          muxed.find((s: any) => s.itag === 22) ||
          muxed.find((s: any) => s.itag === 18) ||
          muxed[0];
        if (best?.url) return best.url;
      }
      if (data.hls) return data.hls;
    } catch {
      // try next instance
    }
  }
  throw new Error('All extraction methods failed');
}

const urlCache = new Map<string, { url: string; expires: number }>();

export const legacyStreamRelayRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.get('/stream', {
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (request: any, reply: any) => {
    // Bypass security headers — AVPlayer needs cross-origin access
    reply.header('Cross-Origin-Resource-Policy', 'cross-origin');
    reply.header('Cross-Origin-Embedder-Policy', 'unsafe-none');
    reply.header('Access-Control-Allow-Origin', '*');
    reply.header('Access-Control-Allow-Headers', 'Range, Content-Type');
    reply.header('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');

    const rawQuery = request.url.split('?')[1] || '';
    const params = new URLSearchParams(rawQuery);
    const videoIdParam = params.get('videoId');
    const b64urlParam = params.get('b64url');
    const urlParam = params.get('url');
    const tokenParam = params.get('token');
    const b64cookiesParam = params.get('b64cookies');
    const b64uaParam = params.get('b64ua');

    if (!tokenParam) return reply.status(401).send({ error: 'Token required' });
    try {
      fastify.jwt.verify(tokenParam);
    } catch {
      return reply.status(401).send({ error: 'Invalid token' });
    }

    let cookieHeader = '';
    if (b64cookiesParam) {
      try {
        cookieHeader = Buffer.from(b64cookiesParam, 'base64').toString('utf-8');
      } catch {
        // ignore
      }
    }

    let userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) ' +
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
    if (b64uaParam) {
      try {
        userAgent = Buffer.from(b64uaParam, 'base64').toString('utf-8');
      } catch {
        // ignore
      }
    }

    let targetUrl: string | null = null;

    if (videoIdParam) {
      const cached = urlCache.get(videoIdParam);
      if (cached && cached.expires > Date.now()) {
        targetUrl = cached.url;
      } else {
        try {
          targetUrl = await extractStreamURLAuthenticated(videoIdParam, cookieHeader, userAgent);
          urlCache.set(videoIdParam, { url: targetUrl, expires: Date.now() + 300000 });
        } catch {
          targetUrl = await extractStreamURL(videoIdParam);
          urlCache.set(videoIdParam, { url: targetUrl, expires: Date.now() + 300000 });
        }
      }
    } else if (b64urlParam) {
      try {
        const decoded = Buffer.from(b64urlParam, 'base64').toString('utf-8');
        let cleaned = decoded.replace(/&amp;/g, '&').replace(/[&?]ip=[^&]+/g, '');
        if (!cleaned.includes('?')) {
          const firstAmp = cleaned.indexOf('&');
          if (firstAmp !== -1) {
            cleaned = cleaned.substring(0, firstAmp) + '?' + cleaned.substring(firstAmp + 1);
          }
        }
        cleaned = cleaned.replace(/&&/g, '&').replace(/[?&]$/, '');
        targetUrl = cleaned;
      } catch {
        return reply.status(400).send({ error: 'Invalid base64' });
      }
    } else if (urlParam) {
      targetUrl = urlParam;
    } else {
      return reply.status(400).send({ error: 'videoId, b64url, or url required' });
    }

    if (!targetUrl) return reply.status(500).send({ error: 'No stream URL' });

    try {
      const upstreamHeaders: Record<string, string> = {
        'User-Agent': userAgent,
        'Referer': 'https://www.youtube.com/',
        'Origin': 'https://www.youtube.com',
      };
      if (cookieHeader) upstreamHeaders['Cookie'] = cookieHeader;
      if (request.headers.range) upstreamHeaders['Range'] = request.headers.range;

      const upstreamRes = await fetch(targetUrl, { headers: upstreamHeaders, redirect: 'follow' });
      if (!upstreamRes.ok && upstreamRes.status !== 206) {
        if (upstreamRes.status === 403 && videoIdParam) {
          urlCache.delete(videoIdParam);
        }
        return reply.status(upstreamRes.status).send({ error: `YouTube ${upstreamRes.status}` });
      }

      if (upstreamRes.body) {
        const nodeStream = Readable.fromWeb(upstreamRes.body as any);
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
        pipeline(nodeStream, raw).catch((err) => {
          if (!raw.destroyed) raw.destroy();
          console.error('[legacyStreamRelay] pipeline error:', err.message);
        });
        return;
      }
      return reply.send(Buffer.alloc(0));
    } catch (e: any) {
      return reply.status(502).send({ error: 'Stream relay failed: ' + e.message });
    }
  });
};

// Safety check: refuse to load if feature flags aren't set for legacy mode.
export function shouldRegisterLegacyRelay(): boolean {
  return !config.APP_STORE_COMPLIANT && config.ENABLE_LEGACY_STREAM_RELAY;
}
