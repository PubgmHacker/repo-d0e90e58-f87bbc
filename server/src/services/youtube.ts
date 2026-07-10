import { execFile } from "child_process";
import { promisify } from "util";
import type { FastifyBaseLogger } from "fastify";

const execFileAsync = promisify(execFile);

// ─── Extracted Media Info ────────────────────────────

export interface ExtractedMedia {
  id: string;
  title: string;
  artist?: string;
  thumbnailURL?: string;
  duration: number;         // seconds
  streamURL: string;        // direct playable URL
  format: string;           // mp4, m3u8, etc.
  quality: string;          // 720p, 1080p, etc.
  fileSize?: number;        // bytes, if known
  isLive: boolean;
}

// ─── YouTube Service ──────────────────────────────────
/**
 * Server-side YouTube video extractor using yt-dlp.
 *
 * Why yt-dlp over npm packages:
 * - npm packages (youtube-dl-wrap, ytdl-core) break frequently due to YouTube changes
 * - yt-dlp is actively maintained, auto-updates, handles extraction reliably
 * - Server-side execution avoids shipping extraction logic to iOS client
 * - Can cache results in Redis
 *
 * Installation:
 *   brew install yt-dlp        (macOS)
 *   apt install yt-dlp         (Ubuntu)
 *   pip install yt-dlp         (Python)
 *
 * Or download binary from: https://github.com/yt-dlp/yt-dlp/releases
 */
export class YouTubeService {
  private ytdlpPath: string;

  constructor(
    private log: FastifyBaseLogger,
    ytdlpPath?: string
  ) {
    this.ytdlpPath = ytdlpPath || process.env.YTDLP_PATH || "yt-dlp";
  }

  /**
   * Extract a direct stream URL from a YouTube link.
   *
   * Strategy:
   * 1. Prefer mp4 (H.264/AAC) — best compatibility with iOS AVPlayer
   * 2. Fallback to m3u8 (HLS) — also supported by AVPlayer
   * 3. Quality target: 720p (balance of quality and bandwidth)
   * 4. Extract thumbnail, title, duration for metadata
   */
  async extract(videoURL: string): Promise<ExtractedMedia> {
    this.log.info({ url: videoURL }, "[YT] Extracting video");

    // Get video info (JSON dump)
    const info = await this.getVideoInfo(videoURL);

    // Find best format for iOS AVPlayer
    const format = this.selectBestFormat(info);

    if (!format) {
      throw new Error("No suitable format found for iOS playback");
    }

    // Get the actual stream URL (yt-dlp resolves it)
    const streamURL = format.url || await this.resolveStreamURL(videoURL, format.format_id);

    const result: ExtractedMedia = {
      id: info.id,
      title: info.title,
      artist: info.channel,
      thumbnailURL: info.thumbnail,
      duration: info.duration,
      streamURL,
      format: format.ext || "mp4",
      quality: format.height ? `${format.height}p` : "unknown",
      fileSize: format.filesize,
      isLive: info.is_live || false,
    };

    this.log.info(
      { id: info.id, title: info.title, quality: result.quality, format: result.format },
      "[YT] Extracted successfully"
    );

    return result;
  }

  /**
   * Get video info using yt-dlp --dump-json
   */
  private async getVideoInfo(url: string): Promise<YTDLpInfo> {
    try {
      // 🔧 v44.1: removed --print json (was duplicating --dump-json output).
      // Also added --no-warnings + --no-call-home + --no-check-certificate
      // to match the flags that worked in earlier versions.
      const { stdout } = await execFileAsync(this.ytdlpPath, [
        "--dump-json",
        "--no-warnings",
        "--no-call-home",
        "--no-check-certificate",
        "--no-playlist",         // Single video only
        "--skip-download",
        "--prefer-free-formats",
        url,
      ], {
        timeout: 30_000,          // 30s timeout
        maxBuffer: 10 * 1024 * 1024, // 10MB buffer (metadata can be large)
      });

      return JSON.parse(stdout) as YTDLpInfo;
    } catch (err: any) {
      this.log.error({ err: err.message, stderr: err.stderr?.toString()?.slice(0, 500) }, "[YT] Failed to get video info");
      throw new Error(`Failed to extract video info. Video may be unavailable or restricted. yt-dlp error: ${err.message}`);
    }
  }

  /**
   * Resolve the actual stream URL for a specific format.
   */
  private async resolveStreamURL(url: string, formatId: string): Promise<string> {
    try {
      const { stdout } = await execFileAsync(this.ytdlpPath, [
        "--get-url",
        "-f", formatId,
        "--no-download",
        url,
      ], {
        timeout: 30_000,
      });

      return stdout.trim();
    } catch (err) {
      this.log.error(err, "[YT] Failed to resolve stream URL");
      throw new Error("Failed to resolve stream URL");
    }
  }

  /**
   * Select the best format for iOS AVPlayer.
   *
   * Priority:
   * 1. MP4 container + H.264 video + AAC audio (universal iOS support)
   * 2. 720p quality (good balance)
   * 3. If no 720p, pick closest resolution
   * 4. Exclude formats that require external players (DASH with separate video/audio)
   */
  private selectBestFormat(info: YTDLpInfo): YTDLpFormat | null {
    if (!info.formats || info.formats.length === 0) {
      // Single format — use it
      if (info.url) {
        return {
          format_id: "best",
          formatId: "best",
          ext: info.ext,
          url: info.url,
          height: info.height,
          width: info.width,
          filesize: info.filesize,
          vcodec: info.vcodec,
          acodec: info.acodec,
        };
      }
      return null;
    }

    // Filter: must have video+audio, mp4 container preferred
    const viableFormats = info.formats.filter((f) =>
      f.ext === "mp4" &&
      f.vcodec !== "none" &&
      f.acodec !== "none" &&
      f.height &&
      f.height >= 480 &&   // At least 480p
      f.height <= 1080 &&  // At most 1080p (bandwidth)
      f.protocol !== "mhtml" &&
      f.url
    );

    // Sort by resolution closeness to 720p
    viableFormats.sort((a, b) => {
      const scoreA = this.formatScore(a, 720);
      const scoreB = this.formatScore(b, 720);
      return scoreB - scoreA;
    });

    if (viableFormats.length > 0) {
      return viableFormats[0];
    }

    // Fallback: any format with both video and audio
    const fallback = info.formats.find((f) =>
      f.vcodec !== "none" &&
      f.acodec !== "none" &&
      f.url &&
      f.protocol !== "mhtml"
    );

    return fallback || null;
  }

  /**
   * Score a format based on how close it is to the target resolution
   * and whether it has desirable codecs.
   */
  private formatScore(format: YTDLpFormat, targetHeight: number): number {
    let score = 100;

    // Resolution proximity
    const heightDiff = Math.abs((format.height || 0) - targetHeight);
    score -= heightDiff * 0.5;

    // Bonus for mp4
    if (format.ext === "mp4") score += 20;

    // Bonus for H.264
    if (format.vcodec?.includes("avc") || format.vcodec?.includes("h264")) score += 15;

    // Bonus for AAC audio
    if (format.acodec?.includes("aac")) score += 10;

    // Penalty for very large files
    if (format.filesize && format.filesize > 2 * 1024 * 1024 * 1024) {
      score -= 30;
    }

    // Penalty for live formats (can be unreliable)
    if (format.is_live) score -= 10;

    return score;
  }

  /**
   * Validate if a URL is a supported YouTube URL
   */
  isSupportedURL(url: string): boolean {
    const patterns = [
      /^https?:\/\/(www\.)?youtube\.com\/watch\?v=[\w-]+/,
      /^https?:\/\/youtu\.be\/[\w-]+/,
      /^https?:\/\/(www\.)?youtube\.com\/shorts\/[\w-]+/,
      /^https?:\/\/(www\.)?youtube\.com\/embed\/[\w-]+/,
    ];
    return patterns.some((p) => p.test(url));
  }

  /**
   * Search YouTube videos using yt-dlp's built-in `ytsearch` extractor.
   * Returns lightweight metadata (no stream URL — that's extracted on pick).
   */
  async search(query: string, limit = 12): Promise<YouTubeSearchResult[]> {
    this.log.info({ query, limit }, "[YT] Searching");

    // Sanitize: strip leading/trailing whitespace, cap length
    const cleanQuery = query.trim().slice(0, 200);
    if (!cleanQuery) return [];

    const searchArg = `ytsearch${limit}:${cleanQuery}`;

    try {
      // --flat-playlist + --print gives us quick metadata without resolving streams
      const { stdout } = await execFileAsync(this.ytdlpPath, [
        searchArg,
        "--flat-playlist",
        "--print",
        "%(id)s\t%(title)s\t%(duration)s\t%(channel)s\t%(thumbnail)s",
        "--no-warnings",
      ], {
        timeout: 20_000,
        maxBuffer: 5 * 1024 * 1024,
      });

      return stdout
        .trim()
        .split("\n")
        .filter(Boolean)
        .map((line) => {
          const [id, title, durationStr, channel, thumbnail] = line.split("\t");
          const duration = durationStr && durationStr !== "NA"
            ? parseFloat(durationStr)
            : undefined;
          return {
            id,
            title: title || "Untitled",
            channel: channel && channel !== "NA" ? channel : undefined,
            thumbnailURL: thumbnail && thumbnail !== "NA" ? thumbnail : undefined,
            duration,
            url: `https://www.youtube.com/watch?v=${id}`,
          } as YouTubeSearchResult;
        })
        .filter((r) => r.id && r.id !== "NA");
    } catch (err) {
      this.log.error(err, "[YT] Search failed");
      throw new Error("YouTube search failed. Try again later.");
    }
  }
}

// ─── Search Result Type ────────────────────────────────

export interface YouTubeSearchResult {
  id: string;
  title: string;
  channel?: string;
  thumbnailURL?: string;
  duration?: number;          // seconds
  url: string;                // canonical watch URL (for extraction later)
}

// ─── yt-dlp JSON Types (simplified) ───────────────────

interface YTDLpInfo {
  id: string;
  title: string;
  channel?: string;
  thumbnail?: string;
  duration: number;
  ext?: string;
  is_live?: boolean;
  url?: string;
  height?: number;
  width?: number;
  vcodec?: string;
  acodec?: string;
  filesize?: number;
  formats?: YTDLpFormat[];
}

interface YTDLpFormat {
  format_id: string;
  formatId?: string;
  ext?: string;
  url?: string;
  height?: number;
  width?: number;
  vcodec?: string;
  acodec?: string;
  filesize?: number;
  protocol?: string;
  is_live?: boolean;
}
