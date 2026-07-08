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
}
