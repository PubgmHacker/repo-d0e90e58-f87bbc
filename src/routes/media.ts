// src/routes/media.ts — Pack 3: обновлённый с yt-dlp extraction
import { extractStream, extractYouTubeStream, extractMetadata } from '../services/streamExtractor.js';
import { cacheGet, cacheSet, cacheDel } from '../config/redis.js';

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
}
