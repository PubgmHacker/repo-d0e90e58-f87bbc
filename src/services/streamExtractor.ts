// src/services/streamExtractor.ts — YouTube stream extraction
// v10.0 (Jan 2027): REPLACED yt-dlp with Piped API as primary extractor.
//   yt-dlp is broken on Railway — "Requested format is not available" error
//   occurs with ALL flag combinations (--dump-json, --print, --skip-download,
//   --no-check-formats). YouTube changed their API and yt-dlp can't extract
//   combined formats from DASH streams without complex format merging.
//
//   Piped API (https://piped-api.kavin.rocks) is a public YouTube proxy that
//   returns direct stream URLs without yt-dlp. It's free, no API key needed,
//   and handles YouTube's DASH format internally.
//
//   Fallback: yt-dlp --print (still broken, but kept as last resort)

import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

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

export const UPSTREAM_USER_AGENT = YT_DLP_UA;

// 🔧 v10.0: Piped API instances — public YouTube proxies.
// If one is down, try the next. All are free, no API key required.
const PIPED_INSTANCES = [
  'https://piped-api.kavin.rocks',
  'https://pipedapi.adminforge.de',
  'https://api.piped.yt',
  'https://pipedapi.r4fo.com',
];

/**
 * Extract video ID from any YouTube URL format.
 */
function extractYouTubeId(url: string): string | null {
  // youtu.be/ID
  const shortMatch = url.match(/youtu\.be\/([\w-]{11})/);
  if (shortMatch) return shortMatch[1];
  // youtube.com/watch?v=ID
  const watchMatch = url.match(/[?&]v=([\w-]{11})/);
  if (watchMatch) return watchMatch[1];
  // youtube.com/embed/ID or youtube.com/shorts/ID
  const embedMatch = url.match(/youtube\.com\/(?:embed|shorts)\/([\w-]{11})/);
  if (embedMatch) return embedMatch[1];
  return null;
}

/**
 * 🔧 v10.0: Extract stream URL using Piped API.
 * Piped returns video info including audioStreams + videoStreams arrays.
 * We pick the best combined stream (or muxed stream if available).
 *
 * Piped API response format:
 *   { title, uploader, thumbnailUrl, duration, audioStreams: [...],
 *     videoStreams: [{ url, format, quality, mimeType, codec: "h264"|"vp9"|...,
 *                      videoOnly: true|false }] }
 *
 * For AVPlayer, we need a "muxed" stream (videoOnly: false) — has both
 * audio + video in one file.
 */
async function extractWithPiped(videoId: string): Promise<StreamInfo> {
  let lastError: string | null = null;

  for (const instance of PIPED_INSTANCES) {
    try {
      const apiUrl = `${instance}/streams/${videoId}`;
      console.log(`[streamExtractor] Trying Piped: ${apiUrl}`);

      const response = await fetch(apiUrl, {
        headers: { 'User-Agent': YT_DLP_UA },
        signal: AbortSignal.timeout(15_000),
      });

      if (!response.ok) {
        lastError = `Piped ${instance} returned ${response.status}`;
        console.error(`[streamExtractor] ${lastError}`);
        continue;
      }

      const data: any = await response.json();
      console.log(`[streamExtractor] Piped ${instance} OK: title="${data.title}", ${data.videoStreams?.length || 0} video streams, ${data.audioStreams?.length || 0} audio streams`);

      // Find best muxed stream (videoOnly: false = has both audio + video)
      const videoStreams = data.videoStreams || [];
      const muxedStreams = videoStreams.filter((s: any) => s.videoOnly === false);

      let bestStream: any = null;
      if (muxedStreams.length > 0) {
        // Sort by quality (e.g., "720p" → 720) descending
        const sorted = muxedStreams.sort((a: any, b: any) => {
          const qa = parseInt(a.quality) || 0;
          const qb = parseInt(b.quality) || 0;
          return qb - qa;
        });
        bestStream = sorted[0];
        console.log(`[streamExtractor] Selected muxed stream: ${bestStream.quality} ${bestStream.format} (${bestStream.mimeType})`);
      }

      // Fallback: if no muxed streams, Piped doesn't provide them.
      // We can't use video-only or audio-only for AVPlayer.
      if (!bestStream) {
        lastError = `Piped ${instance}: no muxed streams (only DASH)`;
        console.error(`[streamExtractor] ${lastError}`);
        continue;
      }

      return {
        id: videoId,
        title: data.title || 'Unknown',
        author: data.uploader || 'Unknown',
        thumbnailURL: data.thumbnailUrl || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
        streamURL: bestStream.url,
        duration: data.duration || 0,
        isLive: data.livestream || false,
        extractor: 'piped',
      };
    } catch (err: any) {
      lastError = `Piped ${instance} error: ${err.message}`;
      console.error(`[streamExtractor] ${lastError}`);
    }
  }

  throw new Error(`All Piped instances failed. Last error: ${lastError}`);
}

/**
 * 🔧 v10.0: Extract stream URL using yt-dlp (fallback, usually broken).
 * Kept as last resort — if Piped is down AND yt-dlp somehow works.
 */
async function extractWithYtDlp(url: string): Promise<StreamInfo> {
  let info: any = { formats: [] };

  try {
    const printResult = await execAsync(
      `yt-dlp --no-warnings --no-call-home --no-playlist ` +
      `--skip-download --no-check-formats ` +
      `--user-agent "${YT_DLP_UA}" ` +
      `--print "%(id)s\\t%(title)s\\t%(thumbnail)s\\t%(duration)s\\t%(uploader)s\\t%(is_live)s\\t%(extractor_key)s\\t%(formats)j" ` +
      `${shellEscape(url)}`,
      { timeout: 30_000, maxBuffer: 10 * 1024 * 1024 }
    );

    const stdout = printResult.stdout.trim();
    const parts = stdout.split('\t');
    if (parts.length < 8) {
      throw new Error(`Unexpected --print output: ${stdout.slice(0, 200)}`);
    }

    info = {
      id: parts[0],
      title: parts[1],
      thumbnail: parts[2],
      duration: parseFloat(parts[3]) || 0,
      uploader: parts[4],
      is_live: parts[5] === 'True' || parts[5] === 'true',
      extractor_key: parts[6],
      formats: [],
    };

    try {
      const formatsData = JSON.parse(parts[7]);
      info.formats = Array.isArray(formatsData) ? formatsData : [];
    } catch {
      console.error('[streamExtractor] Failed to parse formats JSON');
    }
  } catch (err: any) {
    const stderr = err.stderr?.toString() || '';
    throw new Error(`yt-dlp --print failed: ${stderr.slice(0, 500) || err.message}`);
  }

  if (!info.formats || info.formats.length === 0) {
    throw new Error('No formats from yt-dlp');
  }

  // Select best combined format
  const combined = info.formats
    .filter((f: any) => f.vcodec && f.vcodec !== 'none' && f.acodec && f.acodec !== 'none')
    .sort((a: any, b: any) => (b.tbr || 0) - (a.tbr || 0));

  let bestFormat = combined[0] || info.formats.find((f: any) => f.format_id === '18') || info.formats[0];

  if (!bestFormat) {
    throw new Error('No suitable format found');
  }

  return {
    id: info.id,
    title: info.title || 'Unknown',
    author: info.uploader || 'Unknown',
    thumbnailURL: info.thumbnail || '',
    streamURL: bestFormat.url,
    duration: info.duration || 0,
    isLive: info.is_live || false,
    extractor: 'yt-dlp',
  };
}

/**
 * 🔧 v10.0: Main extraction function — tries Piped first, yt-dlp as fallback.
 */
export async function extractStream(url: string): Promise<StreamInfo> {
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Invalid URL protocol');
  }

  // Extract YouTube video ID
  const videoId = extractYouTubeId(url);
  if (videoId) {
    // YouTube: try Piped first (reliable, no yt-dlp issues)
    try {
      console.log(`[streamExtractor] YouTube video ${videoId} — trying Piped API`);
      return await extractWithPiped(videoId);
    } catch (pipedErr: any) {
      console.error(`[streamExtractor] Piped failed: ${pipedErr.message}, trying yt-dlp`);
      // Fall through to yt-dlp
    }
  }

  // Fallback: yt-dlp (may fail, but try)
  return await extractWithYtDlp(url);
}

export async function extractMetadata(url: string): Promise<Partial<StreamInfo>> {
  // For YouTube, use Piped
  const videoId = extractYouTubeId(url);
  if (videoId) {
    try {
      const stream = await extractWithPiped(videoId);
      return {
        id: stream.id,
        title: stream.title,
        author: stream.author,
        thumbnailURL: stream.thumbnailURL,
        duration: stream.duration,
        isLive: stream.isLive,
        extractor: stream.extractor,
      };
    } catch {
      // Fall through to yt-dlp
    }
  }

  // Fallback: yt-dlp
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
