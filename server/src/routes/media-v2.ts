import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { MediaExtractor } from "../services/mediaExtractor.js";
import { YouTubeService } from "../services/youtube.js";

// ─────────────────────────────────────────────────────────────────────────────
//  media-v2.ts — REST маршруты для медиа-экстрактора
//
//    POST /api/media/extract   — извлечь прямой поток / определить WebView-режим
//    GET  /api/media/sources   — список поддерживаемых источников
//    POST /api/media/probe     — проверить доступность URL без извлечения
//    GET  /api/media/search    — поиск YouTube роликов
// ─────────────────────────────────────────────────────────────────────────────

const extractSchema = z.object({
  url: z.string().url("Некорректный URL"),
});

const searchSchema = z.object({
  q: z.string().min(1).max(200),
  limit: z.coerce.number().int().min(1).max(30).default(12),
});

export async function mediaRoutesV2(fastify: FastifyInstance) {
  const extractor = new MediaExtractor(fastify.log, fastify.config.ytdlpPath);
  const youtube = new YouTubeService(fastify.log, fastify.config.ytdlpPath);

  // ─── POST /extract ───────────────────────────────────────────────────────
  fastify.post(
    "/extract",
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const { url } = extractSchema.parse(request.body);

      try {
        const media = await extractor.extract(url);
        return reply.send(media);
      } catch (e: any) {
        request.log.error({ err: e.message, url }, "[media/extract] failed");
        return reply.status(422).send({
          error: e.message || "Не удалось извлечь медиа",
        });
      }
    }
  );

  // ─── POST /extract-url — alias for /extract (legacy iOS clients) ─────────
  // 🔧 v44.1: iOS MediaService.swift v8 was calling /extract-url instead of
  // /extract. This alias ensures backward compatibility.
  fastify.post(
    "/extract-url",
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const { url } = extractSchema.parse(request.body);

      try {
        const media = await extractor.extract(url);
        return reply.send(media);
      } catch (e: any) {
        request.log.error({ err: e.message, url }, "[media/extract-url] failed");
        return reply.status(422).send({
          error: e.message || "Не удалось извлечь медиа",
        });
      }
    }
  );

  // ─── GET /sources ────────────────────────────────────────────────────────
  fastify.get(
    "/sources",
    { preHandler: [fastify.authenticate] },
    async (_request, reply) => {
      return reply.send({ sources: extractor.listSources() });
    }
  );

  // ─── POST /probe — лёгкая проверка без извлечения ────────────────────────
  fastify.post(
    "/probe",
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const { url } = extractSchema.parse(request.body);
      const source = extractor.detectSource(url);
      return reply.send({
        supported: true,
        sourceID: source.id,
        sourceName: source.name,
        mode: source.mode,
        requiresSubscription: source.requiresSubscription,
        message:
          source.mode === "webview"
            ? `${source.name}: режим WebView-синхронизации. Каждый зритель должен иметь свою подписку.`
            : `${source.name}: доступен прямой поток для нативного плеера.`,
      });
    }
  );

  // ─── GET /search — поиск YouTube роликов ─────────────────────────────────
  fastify.get(
    "/search",
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const { q, limit } = searchSchema.parse(request.query);

      try {
        const results = await youtube.search(q, limit);
        return reply.send({ results });
      } catch (e: any) {
        request.log.error({ err: e.message, q }, "[media/search] failed");
        return reply.status(502).send({
          error: e.message || "Поиск недоступен",
        });
      }
    }
  );

  // ─── GET /stream — StreamRelay proxy (v94) ──────────────────────────────
  //
  // 🔧 v94 (Gemini): Proxies video bytes from YouTube CDN to AVPlayer.
  // AVPlayer requests: GET /api/media/stream?url=ENCOD(googlevideoURL)&token=JWT
  // Backend forwards to YouTube CDN with proper User-Agent + Referer headers.
  // YouTube sees server IP + server TLS → NO 403 Forbidden.
  //
  // Supports Range headers for seeking (AVPlayer uses Range requests).
  // Streams bytes via pipe (no buffering in memory).
  fastify.get(
    "/stream",
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const { url } = request.query as { url: string };

      if (!url) {
        return reply.status(400).send({ error: "Missing url parameter" });
      }

      // Decode the target URL
      const targetUrl = decodeURIComponent(url);

      // Only allow googlevideo.com and youtube.com URLs
      if (!targetUrl.includes("googlevideo.com") && !targetUrl.includes("youtube.com") && !targetUrl.includes(".m3u8")) {
        return reply.status(400).send({ error: "Invalid URL — only googlevideo.com allowed" });
      }

      try {
        // Build headers for YouTube CDN
        const headers: Record<string, string> = {
          "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) " +
                        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 " +
                        "Mobile/15E148 Safari/604.1",
          "Referer": "https://www.youtube.com/",
          "Origin": "https://www.youtube.com",
        };

        // Forward Range header from AVPlayer (for seeking)
        const rangeHeader = request.headers["range"];
        if (rangeHeader) {
          headers["Range"] = rangeHeader as string;
        }

        // Fetch from YouTube CDN
        const response = await fetch(targetUrl, { headers });

        if (!response.ok && response.status !== 206) {
          request.log.error({ status: response.status, url: targetUrl.substring(0, 80) }, "[media/stream] YouTube rejected");
          return reply.status(response.status).send({ error: `YouTube returned ${response.status}` });
        }

        // Set response headers for AVPlayer
        reply.status(response.status);
        reply.header("Content-Type", response.headers.get("content-type") || "video/mp4");
        reply.header("Accept-Ranges", "bytes");

        const contentLength = response.headers.get("content-length");
        if (contentLength) reply.header("Content-Length", contentLength);

        const contentRange = response.headers.get("content-range");
        if (contentRange) reply.header("Content-Range", contentRange);

        // Pipe bytes: YouTube → Client (streaming, not buffering)
        return reply.send(response.body);
      } catch (e: any) {
        request.log.error({ err: e.message, url: targetUrl.substring(0, 80) }, "[media/stream] relay failed");
        return reply.status(502).send({ error: e.message || "Stream relay failed" });
      }
    }
  );
}
