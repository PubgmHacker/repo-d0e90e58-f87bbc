// src/services/streamExtractor.ts — yt-dlp wrapper для извлечения прямых stream URLs
// v9.6 (Jan 2027): fixed "Requested format is not available" error.
//   Problem: --prefer-free-formats without -f flag caused yt-dlp to fail
//   when no combined format was available (YouTube now uses DASH).
//   Solution: use -f "best" to let yt-dlp pick ANY best format, then
//   our code selects the best combined format from info.formats array.

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
 *
 * 🔧 v9.6: Fixed "Requested format is not available" error.
 *   - Removed --prefer-free-formats (was causing format selection failures)
 *   - Use -f "best" so yt-dlp picks any best format and returns info.formats
 *   - Our code then selects the best COMBINED format (video+audio in one file)
 *     which AVPlayer can play natively
 *
 * Format selection priority:
 *   1. Combined formats (vcodec != none AND acodec != none) — best for AVPlayer
 *   2. itag 18 (360p mp4, always combined) — universal fallback
 *   3. info.url (single-format videos)
 *   4. First available format (last resort)
 */
export async function extractStream(url: string): Promise<StreamInfo> {
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Invalid URL protocol');
  }

  // 🔧 v9.9: COMPLETELY BYPASS format selection using --print.
  // v9.8 failed because:
  //   - --dump-json STILL triggers format selection internally (even with --skip-download)
  //   - --list-formats-as-json DOESN'T EXIST in yt-dlp (error: no such option)
  //
  // The ONLY way to get format info without triggering selection is --print
  // with a template. --print outputs template values WITHOUT selecting a format:
  //   yt-dlp --print "%(id)s\t%(title)s\t%(thumbnail)s\t%(duration)s\t%(formats)j" URL
  //
  // This gives us tab-separated: id, title, thumbnail, duration, formats_json
  // Then we parse formats_json and pick the best combined format ourselves.

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
    // Split on first 7 tabs (formats JSON may contain tabs? unlikely but safe)
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

    // Parse formats JSON (last field)
    try {
      const formatsData = JSON.parse(parts[7]);
      info.formats = Array.isArray(formatsData) ? formatsData : [];
    } catch {
      console.error('[streamExtractor] Failed to parse formats JSON');
    }

    console.log(`[streamExtractor] --print succeeded: title="${info.title}", ${info.formats.length} formats, duration=${info.duration}s`);
  } catch (err: any) {
    const stderr = err.stderr?.toString() || '';
    console.error('[streamExtractor] --print failed:', stderr.slice(0, 1000));
    throw new Error(`yt-dlp --print failed (code ${err.code}): ${stderr.slice(0, 500) || err.message}`);
  }

  // If we still have no formats, we can't proceed
  if (!info.formats || info.formats.length === 0) {
    throw new Error('No formats available from yt-dlp --print');
  }

  // 🔧 v9.6: broader format search
  let bestFormat: any = null;
  const allFormats = info.formats || [];

  // Priority 1: combined formats (video+audio in one file) — AVPlayer can play these
  // Sort by total bitrate (tbr) descending — highest quality first
  const combined = allFormats
    .filter((f: any) => f.vcodec && f.vcodec !== 'none' && f.acodec && f.acodec !== 'none')
    .sort((a: any, b: any) => (b.tbr || 0) - (a.tbr || 0));

  if (combined.length > 0) {
    bestFormat = combined[0];
    console.log(`[streamExtractor] Selected combined format: ${bestFormat.format_id} (${bestFormat.ext}, ${bestFormat.height}p, tbr=${bestFormat.tbr})`);
  }

  // Priority 2: itag 18 (360p mp4, always combined)
  if (!bestFormat) {
    bestFormat = allFormats.find((f: any) => f.format_id === '18');
    if (bestFormat) console.log(`[streamExtractor] Fallback to itag 18 (360p mp4)`);
  }

  // Priority 3: info.url (some extractors provide a direct URL)
  if (!bestFormat && info.url) {
    bestFormat = { url: info.url, ext: 'mp4', vcodec: 'h264', acodec: 'aac', tbr: 0 };
    console.log(`[streamExtractor] Fallback to info.url`);
  }

  // Priority 4: first available format (last resort — may be video-only or audio-only)
  if (!bestFormat && allFormats.length > 0) {
    bestFormat = allFormats[0];
    console.log(`[streamExtractor] Last resort: first format ${bestFormat.format_id} (may be video-only or audio-only)`);
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
