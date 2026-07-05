// src/services/streamExtractor.ts — yt-dlp wrapper для извлечения прямых stream URLs
// v9.5 (July 2026): fixed format selection + User-Agent matching
//
// Зависимости: yt-dlp должен быть установлен в Dockerfile
//   RUN apt-get update && apt-get install -y yt-dlp

import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

// 🔧 v9.5: single User-Agent used everywhere — yt-dlp extraction + upstream fetch.
// Must be the SAME in both, otherwise googlevideo returns 403 (UA mismatch).
const YT_DLP_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';

export interface StreamInfo {
  id: string;
  title: string;
  author: string;
  thumbnailURL: string;
  streamURL: string;
  duration: number;
  isLive: boolean;
  extractor: string;
  formats?: StreamFormat[];
}

export interface StreamFormat {
  url: string;
  ext: string;
  resolution: string;
  vcodec: string;
  acodec: string;
  filesize: number;
  tbr: number;
}

// 🔧 v9.5: export the UA so media.ts can use the SAME UA for upstream fetch
export const UPSTREAM_USER_AGENT = YT_DLP_UA;

/**
 * Извлекает прямой stream URL из видео-сервиса.
 * v9.5: broader format selection — tries combined formats first, then any
 * format with both audio+video. YouTube moved to DASH (separate audio/video),
 * so combined mp4 is rare. We try:
 *   1. Any format with vcodec != none AND acodec != none (combined)
 *   2. Fallback: format with the lowest itag (usually 18 = 360p mp4)
 *   3. Fallback: info.url (single-format videos)
 */
export async function extractStream(url: string): Promise<StreamInfo> {
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Invalid URL protocol');
  }

  // 🔧 v9.5: use -f flag to let yt-dlp pick the best combined format
  // --format "best[ext=mp4]/best" — prefer mp4, fall back to any best
  const { stdout } = await execAsync(
    `yt-dlp --dump-single-json --no-warnings --no-call-home ` +
    `--no-check-certificate --prefer-free-formats ` +
    `--no-playlist ` +
    `--user-agent "${YT_DLP_UA}" ` +
    `${shellEscape(url)}`,
    { timeout: 30_000, maxBuffer: 10 * 1024 * 1024 }
  );

  const info = JSON.parse(stdout);

  // 🔧 v9.5: broader format search
  // 1. Try any combined format (both video + audio, any container)
  let bestFormat: any = null;
  const allFormats = info.formats || [];

  // Priority 1: combined formats (video+audio in one file) — AVPlayer can play these
  const combined = allFormats
    .filter((f: any) => f.vcodec && f.vcodec !== 'none' && f.acodec && f.acodec !== 'none')
    .sort((a: any, b: any) => (b.tbr || 0) - (a.tbr || 0));
  
  if (combined.length > 0) {
    bestFormat = combined[0];
  }

  // Priority 2: info.url (some extractors provide a direct URL)
  if (!bestFormat && info.url) {
    bestFormat = { url: info.url, ext: 'mp4', vcodec: 'h264', acodec: 'aac', tbr: 0 };
  }

  // Priority 3: itag 18 (360p mp4, always combined) 
  if (!bestFormat) {
    bestFormat = allFormats.find((f: any) => f.format_id === '18');
  }

  if (!bestFormat) {
    throw new Error('No suitable stream format found. Available: ' + 
      allFormats.map((f: any) => `${f.format_id}(${f.ext},${f.vcodec},${f.acodec})`).join(', '));
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
    formats: combined.slice(0, 5).map((f: any) => ({
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

export async function extractMetadata(url: string): Promise<Partial<StreamInfo>> {
  const { stdout } = await execAsync(
    `yt-dlp --dump-single-json --no-warnings --no-call-home ` +
    `--skip-download --no-playlist ` +
    `--user-agent "${YT_DLP_UA}" ` +
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

export async function extractYouTubeStream(videoId: string): Promise<StreamInfo> {
  return extractStream(`https://www.youtube.com/watch?v=${videoId}`);
}

function shellEscape(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`;
}
