// src/routes/ai.ts — Pack 6: AI Assistant endpoint
import { prisma } from '../config/db.js';

const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

export default async function aiRoutes(fastify) {
  
  // POST /api/ai/chat — universal AI assistant
  fastify.post('/ai/chat', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const { messages, context, mode } = request.body;
    
    if (!OPENROUTER_API_KEY) {
      return reply.status(503).send({ 
        error: 'AI not configured. Set OPENROUTER_API_KEY env var.' 
      });
    }
    
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return reply.status(400).send({ error: 'Messages array required' });
    }
    
    // System prompt depends on mode
    const systemPrompt = buildSystemPrompt(mode, context, request.user);
    
    try {
      const response = await fetch(OPENROUTER_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
          'HTTP-Referer': 'https://plink.app',
          'X-Title': 'Plink AI Assistant',
        },
        body: JSON.stringify({
          model: 'openai/gpt-4o-mini',
          messages: [
            { role: 'system', content: systemPrompt },
            ...messages,
          ],
          temperature: 0.7,
          max_tokens: 1000,
        }),
      });
      
      if (!response.ok) {
        const errText = await response.text();
        console.error('OpenRouter error', response.status, errText);
        return reply.status(response.status).send({ 
          error: 'AI request failed',
          details: errText,
        });
      }
      
      const data: any = await response.json();
      const aiMessage = data.choices?.[0]?.message?.content || '';
      
      reply.send({
        message: aiMessage,
        model: data.model,
        usage: data.usage,
      });
    } catch (e: any) {
      console.error('AI chat error', e);
      reply.status(500).send({ error: 'AI request failed: ' + e.message });
    }
  });
  
  // POST /api/ai/recommend — recommend movies/shows based on mood
  fastify.post('/ai/recommend', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const { mood, genre, service } = request.body;
    
    if (!OPENROUTER_API_KEY) {
      return reply.status(503).send({ error: 'AI not configured' });
    }
    
    const prompt = buildRecommendationPrompt(mood, genre, service);
    
    try {
      const response = await fetch(OPENROUTER_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
          'HTTP-Referer': 'https://plink.app',
          'X-Title': 'Plink AI',
        },
        body: JSON.stringify({
          model: 'openai/gpt-4o-mini',
          messages: [
            { role: 'system', content: 'You are a movie/TV recommendation expert. Return JSON only.' },
            { role: 'user', content: prompt },
          ],
          temperature: 0.8,
          max_tokens: 800,
          response_format: { type: 'json_object' },
        }),
      });
      
      if (!response.ok) {
        return reply.status(response.status).send({ error: 'AI request failed' });
      }
      
      const data: any = await response.json();
      const content = data.choices?.[0]?.message?.content || '{}';
      
      try {
        const parsed = JSON.parse(content);
        reply.send(parsed);
      } catch {
        reply.send({ recommendations: [], raw: content });
      }
    } catch (e: any) {
      reply.status(500).send({ error: 'AI request failed: ' + e.message });
    }
  });
}

function buildSystemPrompt(mode: string, context: any, user: any): string {
  const base = `You are Plink AI Assistant — a friendly helper inside Plink, an app for watching movies and shows together with friends in real-time.

User context:
- Username: ${user.username}
- Language: detect from user message and respond in same language
- Be concise but warm. Use emojis occasionally. Don't be overly formal.

`;
  
  switch (mode) {
    case 'room_host':
      return base + `The user is hosting a watch party. Help them with:
- Setting up the room
- Choosing what to watch
- Solving sync issues
- Inviting friends
Context: ${JSON.stringify(context || {})}`;
      
    case 'movie_search':
      return base + `The user is looking for something to watch. Help them:
- Suggest movies/shows based on their mood
- Find content available on streaming services
- Give brief descriptions without spoilers
Context: ${JSON.stringify(context || {})}`;
      
    case 'general':
    default:
      return base + `Help the user with any question about Plink, movies, or general chat. Be helpful and friendly.`;
  }
}

function buildRecommendationPrompt(mood: string, genre: string, service: string): string {
  return `Suggest 5 movies or shows to watch with friends.

Criteria:
- Mood: ${mood || 'any'}
- Genre: ${genre || 'any'}
- Available on: ${service || 'any streaming service'}
- Good for group watching

Return JSON in this exact format:
{
  "recommendations": [
    {
      "title": "Movie Name",
      "year": 2024,
      "genre": "Comedy",
      "service": "Netflix",
      "reason": "Why it's good for groups (1 sentence)",
      "rating": 8.5
    }
  ]
}`;
}
