// This file should replace src/routes/media.ts in the plink-backend repo.
// Copy it manually: cp media_youtube_stream.ts plink-backend/src/routes/media.ts

import { extractStream, extractYouTubeStream, extractMetadata } from '../services/streamExtractor.js';
import { cacheGet, cacheSet, cacheDel } from '../config/redis.js';

const EXTRACT_CACHE_TTL = 3600;

export default async function mediaRoutes(fastify, _options) {
  const YOUTUBE_API_KEY = process.env.YOUTUBE_API_KEY;

  // [existing endpoints: /media/search, /media/extract, /media/extract-url, /media/metadata]
  // ... (keep existing code, only update the youtube-stream endpoint below)

  // ═════════════════════════════════════════════════════════════════════════
  // GET /api/media/youtube-stream?id=VIDEO_ID — Streaming Proxy (v9.1 July 2026)
  // ═════════════════════════════════════════════════════════════════════════
  //
  // v9.1: REMOVED JWT auth. AVPlayer's header injection is unreliable.
  // The video ID is not sensitive — endpoint is now public.
  // Rate limiting still prevents abuse.

  fastify.get('/media/youtube-stream', {
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const { id } = request.query;
    if (!id || typeof id !== 'string' || id.length > 20) {
      return reply.status(400).send({ error: 'Valid video ID required' });
    }

    // ── 1. Extract googlevideo URL (cached) ──────────────────────────
    const cacheKey = `yt:stream:${id}`;
    let streamInfo = await cacheGet(cacheKey);
    if (!streamInfo) {
      try {
        streamInfo = await extractYouTubeStream(id);
        await cacheSet(cacheKey, streamInfo, EXTRACT_CACHE_TTL);
      } catch (e) {
        console.error('[youtube-stream] extract error', e.message);
        return reply.status(500).send({ error: 'Extract failed: ' + e.message });
      }
    }

    const upstreamUrl = streamInfo.streamURL;
    if (!upstreamUrl) {
      return reply.status(500).send({ error: 'No stream URL available' });
    }

    // ── 2. Fetch from googlevideo (IP-bound to Railway = matches) ─────
    const rangeHeader = request.headers.range;
    const upstreamHeaders = {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
      'Referer': 'https://www.youtube.com/',
      'Origin': 'https://www.youtube.com',
    };
    if (rangeHeader) {
      upstreamHeaders['Range'] = rangeHeader;
    }

    try {
      const upstreamRes = await fetch(upstreamUrl, { headers: upstreamHeaders, redirect: 'follow' });

      if (!upstreamRes.ok && upstreamRes.status !== 206) {
        console.error('[youtube-stream] upstream error', upstreamRes.status);
        return reply.status(502).send({ error: `Upstream returned ${upstreamRes.status}` });
      }

      // ── 3. Stream upstream response back to client ─────────────────
      reply.code(upstreamRes.status);
      reply.header('Content-Type', upstreamRes.headers.get('content-type') || 'video/mp4');
      reply.header('Accept-Ranges', 'bytes');
      const cl = upstreamRes.headers.get('content-length');
      if (cl) reply.header('Content-Length', cl);
      const cr = upstreamRes.headers.get('content-range');
      if (cr) reply.header('Content-Range', cr);
      reply.header('Cache-Control', 'public, max-age=3600');

      // Use raw response for proper streaming
      if (upstreamRes.body) {
        const reader = upstreamRes.body.getReader();
        const raw = reply.raw;
        const headers = {
          'Content-Type': upstreamRes.headers.get('content-type') || 'video/mp4',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=3600',
        };
        if (cl) headers['Content-Length'] = cl;
        if (cr) headers['Content-Range'] = cr;
        raw.writeHead(upstreamRes.status, headers);

        const pump = async () => {
          try {
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              if (!raw.destroyed) raw.write(Buffer.from(value));
            }
            raw.end();
          } catch (err) {
            console.error('[youtube-stream] pump error', err.message);
            if (!raw.destroyed) raw.end();
          }
        };
        pump();
        return reply;
      } else {
        return reply.send(Buffer.alloc(0));
      }
    } catch (e) {
      console.error('[youtube-stream] proxy error', e.message);
      return reply.status(500).send({ error: 'Stream proxy failed: ' + e.message });
    }
  });
}
