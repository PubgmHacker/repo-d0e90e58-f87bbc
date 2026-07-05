// src/routes/media.ts — Pack 3: обновлённый с yt-dlp extraction
import { extractStream, extractYouTubeStream, extractMetadata } from '../services/streamExtractor.js';
import { cacheGet, cacheSet, cacheDel } from '../config/redis.js';
import { Readable } from 'stream';
import { request as httpRequest } from 'http';
import { request as httpsRequest } from 'https';

const EXTRACT_CACHE_TTL = 3600; // 1 час — прямой URL живёт долго

export default async function mediaRoutes(fastify, _options) {
  const YOUTUBE_API_KEY = process.env.YOUTUBE_API_KEY;

  // ═══════════════════════════════════════════════════════════════════
  // GET /api/media/search?q=запрос&limit=12 — YouTube поиск
  // ═══════════════════════════════════════════════════════════════════
  fastify.get('/media/search', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
  }, async (request: any, reply: any) => {
    const { q, limit = '12' } = request.query as any;

    if (!q) return reply.status(400).send({ error: 'Query required' });
    if (!YOUTUBE_API_KEY) {
      return reply.status(500).send({ error: 'YOUTUBE_API_KEY not configured' });
    }

    // Cache key
    const cacheKey = `yt:search:${q}:${limit}`;
    const cached = await cacheGet<any[]>(cacheKey);
    if (cached) return reply.send({ results: cached });

    const url = new URL('https://www.googleapis.com/youtube/v3/search');
    url.searchParams.set('part', 'snippet');
    url.searchParams.set('q', q);
    url.searchParams.set('type', 'video');
    url.searchParams.set('maxResults', String(limit));
    url.searchParams.set('key', YOUTUBE_API_KEY);

    try {
      const resp = await fetch(url.toString());
      if (!resp.ok) {
        const errText = await resp.text();
        console.error('YouTube API error', resp.status, errText);
        return reply.status(resp.status).send({ error: 'YouTube API error' });
      }
      const data: any = await resp.json();

      const results = (data.items || [])
        .filter((item: any) => item.id?.videoId)
        .map((item: any) => ({
          id: item.id.videoId,
          title: item.snippet?.title || '',
          channel: item.snippet?.channelTitle || '',
          thumbnailURL: item.snippet?.thumbnails?.medium?.url ||
                        item.snippet?.thumbnails?.default?.url || null,
          duration: null,
        }));

      await cacheSet(cacheKey, results, 600); // 10 min
      reply.send({ results });
    } catch (e: any) {
      console.error('Search error', e);
      reply.status(500).send({ error: 'Search failed' });
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // GET /api/media/extract?id=VIDEO_ID — YouTube stream extraction (yt-dlp)
  // ═══════════════════════════════════════════════════════════════════
  fastify.get('/media/extract', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } }
  }, async (request: any, reply: any) => {
    const { id } = request.query as any;
    if (!id) return reply.status(400).send({ error: 'Video ID required' });

    // Cache extraction (URL YouTube живёт ~6 часов)
    const cacheKey = `yt:stream:${id}`;
    const cached = await cacheGet<any>(cacheKey);
    if (cached) {
      return reply.send(cached);
    }

    try {
      const stream = await extractYouTubeStream(id);
      await cacheSet(cacheKey, stream, EXTRACT_CACHE_TTL);
      reply.send(stream);
    } catch (e: any) {
      console.error('YouTube extract error', e.message);
      
      // Fallback: oEmbed (только метаданные, без streamURL)
      try {
        const oembedUrl = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${id}&format=json`;
        const resp = await fetch(oembedUrl);
        if (resp.ok) {
          const data: any = await resp.json();
          return reply.send({
            id,
            title: data.title,
            author: data.author_name,
            thumbnailURL: data.thumbnail_url,
            embedURL: `https://www.youtube.com/embed/${id}?autoplay=1&playsinline=1&rel=0`,
            watchURL: `https://www.youtube.com/watch?v=${id}`,
            streamURL: null,  // не удалось извлечь прямой поток
            fallback: 'embed',
          });
        }
      } catch {}
      
      reply.status(500).send({ error: 'Extract failed: ' + e.message });
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // POST /api/media/extract-url — извлечение по любому URL (VK, RuTube, etc.)
  // ═══════════════════════════════════════════════════════════════════
  fastify.post('/media/extract-url', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } }
  }, async (request: any, reply: any) => {
    const { url } = request.body;
    if (!url) return reply.status(400).send({ error: 'URL required' });

    const cacheKey = `stream:${Buffer.from(url).toString('base64').slice(0, 40)}`;
    const cached = await cacheGet<any>(cacheKey);
    if (cached) return reply.send(cached);

    try {
      const stream = await extractStream(url);
      await cacheSet(cacheKey, stream, EXTRACT_CACHE_TTL);
      reply.send(stream);
    } catch (e: any) {
      console.error('Extract URL error', e.message);
      reply.status(500).send({ error: 'Extract failed: ' + e.message });
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // GET /api/media/metadata?url=... — только метаданные (без stream)
  // ═══════════════════════════════════════════════════════════════════
  fastify.get('/media/metadata', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } }
  }, async (request: any, reply: any) => {
    const { url } = request.query as any;
    if (!url) return reply.status(400).send({ error: 'URL required' });

    const cacheKey = `meta:${Buffer.from(url).toString('base64').slice(0, 40)}`;
    const cached = await cacheGet<any>(cacheKey);
    if (cached) return reply.send(cached);

    try {
      const meta = await extractMetadata(url);
      await cacheSet(cacheKey, meta, 3600);
      reply.send(meta);
    } catch (e: any) {
      reply.status(500).send({ error: 'Metadata failed: ' + e.message });
    }
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GET /api/media/youtube-stream?id=VIDEO_ID — Streaming Proxy (v9 July 2026)
  // ═════════════════════════════════════════════════════════════════════════
  //
  // PROBLEM: googlevideo URLs are IP-bound. yt-dlp extracts a URL containing
  // &ip=<railway_ip>. When AVPlayer on iPhone requests from a different IP,
  // YouTube returns 403 → AVPlayer fails with -11828.
  //
  // SOLUTION: backend acts as a reverse proxy. iPhone requests this endpoint,
  // backend extracts the googlevideo URL (IP-bound to Railway), then fetches
  // the video from googlevideo (IP matches → 200 OK), and streams it back
  // to iPhone. AVPlayer sees a Railway URL, not a googlevideo URL.
  //
  // Supports HTTP Range requests for seeking — passes Range header through
  // to googlevideo and passes Content-Range back to client.
  //
  // Cache: extraction results cached 1hr (googlevideo URLs live ~6hrs).
  // The proxy itself doesn't cache video data (would consume too much RAM).
  //
  // Auth: requires JWT (prevents anonymous abuse).
  // Rate limit: 20 requests/minute (each request = 1 yt-dlp extraction).

  fastify.get('/media/youtube-stream', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } }
  }, async (request: any, reply: any) => {
    const { id } = request.query as any;
    if (!id) return reply.status(400).send({ error: 'Video ID required' });

    // ── 1. Extract googlevideo URL (cached) ──────────────────────────
    const cacheKey = `yt:stream:${id}`;
    let streamInfo: any = await cacheGet<any>(cacheKey);
    if (!streamInfo) {
      try {
        streamInfo = await extractYouTubeStream(id);
        await cacheSet(cacheKey, streamInfo, EXTRACT_CACHE_TTL);
      } catch (e: any) {
        console.error('[youtube-stream] extract error', e.message);
        return reply.status(500).send({ error: 'Extract failed: ' + e.message });
      }
    }

    const upstreamUrl = streamInfo.streamURL;
    if (!upstreamUrl) {
      return reply.status(500).send({ error: 'No stream URL available' });
    }

    // ── 2. Fetch from googlevideo (IP-bound to Railway = matches) ─────
    // Pass through Range header for seeking support.
    const rangeHeader = request.headers.range;
    const upstreamHeaders: any = {
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
      // 🔧 v9.2: replaced Readable.fromWeb with manual pump.
      // Readable.fromWeb doesn't work reliably on Railway's Node.js,
      // causing -1008 'Ресурс недоступен' on AVPlayer.
      // Manual pump using reader.read() + raw.write() works everywhere.
      if (upstreamRes.body) {
        const reader = upstreamRes.body.getReader();
        const raw = reply.raw;
        const respHeaders: Record<string, string> = {
          'Content-Type': upstreamRes.headers.get('content-type') || 'video/mp4',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=3600',
        };
        const cl = upstreamRes.headers.get('content-length');
        if (cl) respHeaders['Content-Length'] = cl;
        const cr = upstreamRes.headers.get('content-range');
        if (cr) respHeaders['Content-Range'] = cr;
        raw.writeHead(upstreamRes.status, respHeaders);

        const pump = async () => {
          try {
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              if (!raw.destroyed) raw.write(Buffer.from(value));
            }
            raw.end();
          } catch (err: any) {
            console.error('[youtube-stream] pump error', err.message);
            if (!raw.destroyed) raw.end();
          }
        };
        pump();
        return reply;
      } else {
        return reply.send(Buffer.alloc(0));
      }
    } catch (e: any) {
      console.error('[youtube-stream] proxy error', e.message);
      return reply.status(500).send({ error: 'Stream proxy failed: ' + e.message });
    }
  });
}
