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

// 🔧 v10.1: Invidious API instances — alternative YouTube proxies.
// Piped instances are often blocked on Railway IPs. Invidious has more
// instances and different blocking patterns, so it's more likely to work.
// Invidious API: GET https://invidious.example.com/api/v1/videos/VIDEO_ID
// Returns: { title, author, lengthSeconds, formatStreams: [{url, type, quality}], adaptiveFormats: [...] }
// formatStreams are muxed (audio+video) — perfect for AVPlayer!
const INVIDIOUS_INSTANCES = [
  'https://invidious.nerdvpn.de',
  'https://invidious.jing.rocks',
  'https://invidious.privacyredirect.com',
  'https://inv.nadeko.net',
  'https://invidious.perennialte.ch',
  'https://iv.ggtyler.dev',
  'https://invidious.einfachzocken.eu',
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

// 🔧 v10.2: youtubei.googleapis.com — YouTube's INTERNAL API.
// This is the same API that youtube.com itself uses. No API key, no yt-dlp.
// Returns streamingData.formats[] (muxed) + streamingData.adaptiveFormats[] (DASH).
// We use formats[] — these are muxed streams AVPlayer can play natively.
//
// This API is what NewPipe and other YouTube alternative clients use.
// It's the most reliable way to extract YouTube streams without yt-dlp.
const YOUTUBEI_CLIENT_VERSION = '1.20240101.0.0';

/**
 * 🔧 v10.2: Extract stream URL using YouTube's internal API (youtubei.googleapis.com).
 * This is what youtube.com itself uses — no API key, no yt-dlp, no proxy needed.
 * Returns streamingData.formats[] which are MUXED (audio+video) streams.
 */
async function extractWithYouTubeI(videoId: string): Promise<StreamInfo> {
  // 🔧 v10.2.3: TVHTML5 client is the key — it's used by Smart TV apps
  // and has DIFFERENT bot detection than WEB/ANDROID/IOS.
  // WEB client returns UNPLAYABLE for many videos on datacenter IPs.
  // TVHTML5 client doesn't trigger bot detection and returns HLS manifest.
  const clients = [
    {
      name: 'TVHTML5',
      clientName: 'TVHTML5',
      clientVersion: '7.20240101.0.0',
      userAgent: 'Mozilla/5.0 (PlayStation; PlayStation 4/12.00) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15',
    },
    {
      name: 'MWEB',
      clientName: 'MWEB',
      clientVersion: '2.20240101.0.0',
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    },
    {
      name: 'WEB',
      clientName: 'WEB',
      clientVersion: '2.20240101.0.0',
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
    {
      name: 'ANDROID',
      clientName: 'ANDROID',
      clientVersion: '19.09.37',
      userAgent: 'com.google.android.youtube/19.09.37 (Linux; U; Android 14; SM-S918B) gzip',
    },
    {
      name: 'IOS',
      clientName: 'IOS',
      clientVersion: '19.09.3',
      userAgent: 'com.google.ios.youtube/19.09.3 (iPhone15,3; U; CPU iOS 15_6 like Mac OS X)',
    },
  ];

  let lastError: string | null = null;

  for (const client of clients) {
    try {
      // 🔧 v10.2.1: use /youtubei/v1/player WITHOUT key for WEB client.
      // The key is only needed for certain clients. Try without key first.
      const apiUrl = 'https://www.youtube.com/youtubei/v1/player';
      console.log(`[streamExtractor] Trying YouTube Internal API (${client.name}) for ${videoId}`);

      const body = {
        context: {
          client: {
            clientName: client.clientName,
            clientVersion: client.clientVersion,
            hl: 'en',
            gl: 'US',
          },
        },
        videoId: videoId,
      };

      const response = await fetch(apiUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': client.userAgent,
          'Accept': 'application/json',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10_000),
      });

      if (!response.ok) {
        lastError = `YouTube Internal API (${client.name}) returned ${response.status}`;
        console.error(`[streamExtractor] ${lastError}`);
        continue;
      }

      const data: any = await response.json();
      const streamingData = data.streamingData || {};
      const formats = streamingData.formats || [];  // Muxed streams!
      const videoDetails = data.videoDetails || {};
      const playabilityStatus = data.playabilityStatus || {};

      console.log(`[streamExtractor] YouTube Internal API (${client.name}) OK: title="${videoDetails.title}", ${formats.length} muxed formats, hls=${!!streamingData.hlsManifestUrl}, dash=${!!streamingData.dashManifestUrl}`);

      // 🔧 v10.2.2: if no muxed formats, try HLS manifest URL.
      // AVPlayer can play HLS (.m3u8) natively — it's adaptive streaming
      // that handles audio+video together. YouTube provides hlsManifestUrl
      // for most videos.
      if (formats.length === 0 && streamingData.hlsManifestUrl) {
        console.log(`[streamExtractor] No muxed formats, using HLS manifest: ${streamingData.hlsManifestUrl.slice(0, 100)}...`);
        return {
          id: videoId,
          title: videoDetails.title || 'Unknown',
          author: videoDetails.author || 'Unknown',
          thumbnailURL: videoDetails.thumbnail?.thumbnails?.pop()?.url ||
                        `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
          streamURL: streamingData.hlsManifestUrl,
          duration: parseInt(videoDetails.lengthSeconds) || 0,
          isLive: videoDetails.isLive || false,
          extractor: 'youtubei-hls',
        };
      }

      if (formats.length === 0) {
        lastError = `YouTube Internal API (${client.name}): no muxed formats and no HLS manifest (playability: ${playabilityStatus.status})`;
        console.error(`[streamExtractor] ${lastError}`);
        continue;
      }

      // Sort by quality (itag 18 = 360p, 22 = 720p, etc.) — prefer higher quality
      const sorted = formats.sort((a: any, b: any) => {
        const qualityOrder: Record<number, number> = { 22: 720, 18: 360, 43: 360, 36: 240, 17: 144 };
        const qa = qualityOrder[a.itag] || parseInt(a.qualityLabel) || 0;
        const qb = qualityOrder[b.itag] || parseInt(b.qualityLabel) || 0;
        return qb - qa;
      });

      const bestFormat = sorted[0];
      console.log(`[streamExtractor] Selected: itag ${bestFormat.itag} (${bestFormat.qualityLabel || 'unknown'}, ${bestFormat.mimeType})`);

      return {
        id: videoId,
        title: videoDetails.title || 'Unknown',
        author: videoDetails.author || 'Unknown',
        thumbnailURL: videoDetails.thumbnail?.thumbnails?.pop()?.url ||
                      `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
        streamURL: bestFormat.url,
        duration: parseInt(videoDetails.lengthSeconds) || 0,
        isLive: videoDetails.isLive || false,
        extractor: 'youtubei',
      };
    } catch (err: any) {
      lastError = `YouTube Internal API (${client.name}) error: ${err.message}`;
      console.error(`[streamExtractor] ${lastError}`);
    }
  }

  throw new Error(`All YouTube Internal API clients failed. Last error: ${lastError}`);
}

/**
 * 🔧 v10.1: Extract stream URL using Invidious API.
 * Invidious returns formatStreams[] (muxed: audio+video) + adaptiveFormats[] (DASH).
 * We use formatStreams — these are direct URLs AVPlayer can play natively.
 *
 * Invidious API response format:
 *   { title, author, lengthSeconds, videoThumbnails: [{url}],
 *     formatStreams: [{url, type, quality}],  ← MUXED streams!
 *     adaptiveFormats: [{url, type, ...}] }   ← DASH (separate a/v)
 */
async function extractWithInvidious(videoId: string): Promise<StreamInfo> {
  let lastError: string | null = null;

  for (const instance of INVIDIOUS_INSTANCES) {
    try {
      const apiUrl = `${instance}/api/v1/videos/${videoId}?fields=title,author,lengthSeconds,videoThumbnails,formatStreams,liveNow`;
      console.log(`[streamExtractor] Trying Invidious: ${apiUrl}`);

      const response = await fetch(apiUrl, {
        headers: {
          'User-Agent': YT_DLP_UA,
          'Accept': 'application/json',
        },
        signal: AbortSignal.timeout(10_000),
      });

      if (!response.ok) {
        lastError = `Invidious ${instance} returned ${response.status}`;
        console.error(`[streamExtractor] ${lastError}`);
        continue;
      }

      const data: any = await response.json();
      const formatStreams = data.formatStreams || [];
      console.log(`[streamExtractor] Invidious ${instance} OK: title="${data.title}", ${formatStreams.length} muxed streams`);

      if (formatStreams.length === 0) {
        lastError = `Invidious ${instance}: no formatStreams (only adaptive)`;
        console.error(`[streamExtractor] ${lastError}`);
        continue;
      }

      // Sort by quality descending (e.g., "720p" → 720)
      const sorted = formatStreams
        .filter((s: any) => s.url)
        .sort((a: any, b: any) => {
          const qa = parseInt(a.quality) || 0;
          const qb = parseInt(b.quality) || 0;
          return qb - qa;
        });

      const bestStream = sorted[0];
      if (!bestStream) {
        lastError = `Invidious ${instance}: no valid stream URLs`;
        console.error(`[streamExtractor] ${lastError}`);
        continue;
      }

      // Get best thumbnail
      const thumbnail = data.videoThumbnails?.[0]?.url ||
                        `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;

      console.log(`[streamExtractor] Selected: ${bestStream.quality} ${bestStream.type}`);

      return {
        id: videoId,
        title: data.title || 'Unknown',
        author: data.author || 'Unknown',
        thumbnailURL: thumbnail,
        streamURL: bestStream.url,
        duration: data.lengthSeconds || 0,
        isLive: data.liveNow || false,
        extractor: 'invidious',
      };
    } catch (err: any) {
      lastError = `Invidious ${instance} error: ${err.message}`;
      console.error(`[streamExtractor] ${lastError}`);
    }
  }

  throw new Error(`All Invidious instances failed. Last error: ${lastError}`);
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
 * 🔧 v10.2: Main extraction function — tries YouTubeI → Invidious → Piped → yt-dlp.
 * YouTubeI is YouTube's OWN internal API — most reliable, no proxy needed.
 */
export async function extractStream(url: string): Promise<StreamInfo> {
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Invalid URL protocol');
  }

  // Extract YouTube video ID
  const videoId = extractYouTubeId(url);
  if (videoId) {
    // YouTube: try YouTube Internal API first (most reliable)
    try {
      console.log(`[streamExtractor] YouTube video ${videoId} — trying YouTube Internal API`);
      return await extractWithYouTubeI(videoId);
    } catch (youtubeiErr: any) {
      console.error(`[streamExtractor] YouTube Internal API failed: ${youtubeiErr.message}`);

      // Fallback: try Invidious
      try {
        console.log(`[streamExtractor] Trying Invidious API`);
        return await extractWithInvidious(videoId);
      } catch (invidiousErr: any) {
        console.error(`[streamExtractor] Invidious failed: ${invidiousErr.message}`);

        // Fallback: try Piped
        try {
          console.log(`[streamExtractor] Trying Piped API`);
          return await extractWithPiped(videoId);
        } catch (pipedErr: any) {
          console.error(`[streamExtractor] Piped failed: ${pipedErr.message}`);
          // Fall through to yt-dlp
        }
      }
    }
  }

  // Last resort: yt-dlp (usually broken, but try)
  console.log(`[streamExtractor] All APIs failed, trying yt-dlp as last resort`);
  return await extractWithYtDlp(url);
}

export async function extractMetadata(url: string): Promise<Partial<StreamInfo>> {
  // For YouTube, try YouTubeI → Invidious → Piped
  const videoId = extractYouTubeId(url);
  if (videoId) {
    try {
      const stream = await extractWithYouTubeI(videoId);
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
      try {
        const stream = await extractWithInvidious(videoId);
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
