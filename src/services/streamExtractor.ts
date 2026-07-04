// src/services/streamExtractor.ts — yt-dlp wrapper для извлечения прямых stream URLs
// Поддерживает: YouTube, VK Видео, RuTube, Vimeo, Dailymotion, и др.
//
// Зависимости: yt-dlp должен быть установлен в Dockerfile
//   RUN apt-get update && apt-get install -y yt-dlp
// (или pip install yt-dlp)

import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs/promises';
import path from 'path';
import os from 'os';

const execAsync = promisify(exec);

export interface StreamInfo {
  id: string;
  title: string;
  author: string;
  thumbnailURL: string;
  streamURL: string;       // прямой URL для AVPlayer
  duration: number;        // секунды
  isLive: boolean;
  extractor: string;       // "youtube", "vk", "rutube", etc.
  formats?: StreamFormat[];
}

export interface StreamFormat {
  url: string;
  ext: string;
  resolution: string;
  vcodec: string;
  acodec: string;
  filesize: number;
  tbr: number; // total bitrate
}

/**
 * Извлекает прямой stream URL из видео-сервиса.
 * Использует yt-dlp под капотом.
 */
export async function extractStream(url: string): Promise<StreamInfo> {
  // Валидация URL
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Invalid URL protocol');
  }

  // Запуск yt-dlp с JSON output
  const { stdout } = await execAsync(
    `yt-dlp --dump-single-json --no-warnings --no-call-home ` +
    `--no-check-certificate --prefer-free-formats ` +
    `--youtube-skip-dash-manifest --no-playlist ` +
    `--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" ` +
    `${shellEscape(url)}`,
    { timeout: 30_000, maxBuffer: 10 * 1024 * 1024 }
  );

  const info = JSON.parse(stdout);

  // Найти лучший mp4 (combined video+audio)
  const formats = (info.formats || [])
    .filter((f: any) => f.ext === 'mp4' && f.vcodec !== 'none' && f.acodec !== 'none')
    .sort((a: any, b: any) => (b.tbr || 0) - (a.tbr || 0));

  const bestFormat = formats[0];
  if (!bestFormat) {
    throw new Error('No suitable stream format found');
  }

  return {
    id: info.id || parsed.searchParams.get('v') || Date.now().toString(),
    title: info.title || 'Unknown',
    author: info.uploader || info.channel || 'Unknown',
    thumbnailURL: info.thumbnail || '',
    streamURL: bestFormat.url,
    duration: info.duration || 0,
    isLive: info.is_live || false,
    extractor: info.extractor_key?.toLowerCase() || 'unknown',
    formats: formats.slice(0, 5).map((f: any) => ({
      url: f.url,
      ext: f.ext,
      resolution: f.resolution || `${f.height}p`,
      vcodec: f.vcodec,
      acodec: f.acodec,
      filesize: f.filesize || 0,
      tbr: f.tbr || 0,
    })),
  };
}

/**
 * Быстрое извлечение только метаданных (без stream URL).
 * Дешевле, используется для предпросмотра в поиске.
 */
export async function extractMetadata(url: string): Promise<Partial<StreamInfo>> {
  const { stdout } = await execAsync(
    `yt-dlp --dump-single-json --no-warnings --no-call-home ` +
    `--skip-download --no-playlist ` +
    `${shellEscape(url)}`,
    { timeout: 15_000, maxBuffer: 2 * 1024 * 1024 }
  );

  const info = JSON.parse(stdout);
  return {
    id: info.id,
    title: info.title,
    author: info.uploader,
    thumbnailURL: info.thumbnail,
    duration: info.duration,
    isLive: info.is_live,
    extractor: info.extractor_key?.toLowerCase(),
  };
}

/**
 * Извлечь stream для YouTube по video ID.
 */
export async function extractYouTubeStream(videoId: string): Promise<StreamInfo> {
  return extractStream(`https://www.youtube.com/watch?v=${videoId}`);
}

function shellEscape(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`;
}
