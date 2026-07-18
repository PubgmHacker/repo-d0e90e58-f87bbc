import type { MediaItem } from './types';

/** Backend origin used for hosted YouTube player (fixes error 153 in Tauri/WebView). */
export const API_ORIGIN =
  import.meta.env.VITE_API_ORIGIN ??
  'https://plink-backend-production-ef31.up.railway.app';

/** Matches iOS embed origin trick — real HTTPS origin for YouTube IFrame API. */
export const YOUTUBE_EMBED_ORIGIN = API_ORIGIN;

const YT_ID = /(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/;
const RUTUBE_ID = /rutube\.ru\/(?:video|play\/embed)\/([a-f0-9]+)/i;
const VK_ID = /vk\.com\/video(-?\d+_\d+)/;

export function extractYouTubeId(input: string): string | null {
  const m = input.match(YT_ID);
  return m?.[1] ?? null;
}

/** Hosted player page — has real HTTPS origin, avoids YouTube 153 in desktop WebView. */
export function youtubeHostedPlayerUrl(videoId: string): string {
  return `${API_ORIGIN}/api/media/youtube-player?id=${encodeURIComponent(videoId)}`;
}

export function parseMediaFromUrl(raw: string, title = 'Shared video'): MediaItem | null {
  const url = raw.trim();
  const yt = extractYouTubeId(url);
  if (yt) return youtubeMediaItem(yt, title);

  const rutube = url.match(RUTUBE_ID);
  if (rutube) {
    const id = rutube[1]!;
    const embed = `https://rutube.ru/play/embed/${id}`;
    return {
      id: embed,
      title,
      streamURL: embed,
      mediaType: 'video',
      source: 'rutube',
      videoId: id,
      thumbnailURL: `https://pic.rutube.ru/${id.slice(0, 2)}/${id.slice(2, 4)}/${id}/m.jpg`,
    };
  }

  const vk = url.match(VK_ID);
  if (vk) {
    const oid = vk[1]!;
    const [oidPart, idPart] = oid.split('_');
    const embed = `https://vk.com/video_ext.php?oid=${oidPart}&id=${idPart}&hd=2`;
    return {
      id: embed,
      title,
      streamURL: embed,
      mediaType: 'video',
      source: 'vk',
      videoId: oid,
    };
  }

  return null;
}

export function youtubeMediaItem(videoId: string, title: string, thumbnailURL?: string): MediaItem {
  return {
    id: videoId,
    title,
    thumbnailURL: thumbnailURL ?? `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
    streamURL: youtubeHostedPlayerUrl(videoId),
    mediaType: 'video',
    source: 'youtube',
    videoId,
  };
}

export function embedUrlForMedia(item: MediaItem): string | null {
  if (item.source === 'youtube' && item.videoId) {
    return youtubeHostedPlayerUrl(item.videoId);
  }
  if (item.source === 'rutube' && item.videoId) {
    return `https://rutube.ru/play/embed/${item.videoId}?skinColor=5ab09b`;
  }
  if (item.source === 'vk' && item.videoId) {
    const [oid, id] = item.videoId.split('_');
    return `https://vk.com/video_ext.php?oid=${oid}&id=${id}&hd=2&autoplay=1`;
  }
  return item.streamURL || null;
}
