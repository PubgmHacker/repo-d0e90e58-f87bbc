export default async function mediaRoutes(fastify, _options) {
  const YOUTUBE_API_KEY = process.env.YOUTUBE_API_KEY;

  // GET /api/media/search?q=запрос&limit=12
  fastify.get('/media/search', {
    preHandler: [fastify.authenticate]
  }, async (request: any, reply: any) => {
    const { q, limit = '12' } = request.query as any;

    if (!q) return reply.status(400).send({ error: 'Query required' });
    if (!YOUTUBE_API_KEY) {
      return reply.status(500).send({ error: 'YOUTUBE_API_KEY not configured' });
    }

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

      reply.send({ results });
    } catch (e: any) {
      console.error('Search error', e);
      reply.status(500).send({ error: 'Search failed' });
    }
  });

  // GET /api/media/extract?id=VIDEO_ID — извлечь метаданные и embed URL
  fastify.get('/media/extract', {
    preHandler: [fastify.authenticate]
  }, async (request: any, reply: any) => {
    const { id } = request.query as any;

    if (!id) return reply.status(400).send({ error: 'Video ID required' });

    try {
      const oembedUrl = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${id}&format=json`;
      const resp = await fetch(oembedUrl);

      if (!resp.ok) {
        return reply.status(404).send({ error: 'Video not found' });
      }

      const data: any = await resp.json();

      reply.send({
        id,
        title: data.title,
        author: data.author_name,
        thumbnailURL: data.thumbnail_url,
        embedURL: `https://www.youtube.com/embed/${id}?autoplay=1&playsinline=1&rel=0`,
        watchURL: `https://www.youtube.com/watch?v=${id}`,
      });
    } catch (e: any) {
      console.error('Extract error', e);
      reply.status(500).send({ error: 'Extract failed' });
    }
  });
}
