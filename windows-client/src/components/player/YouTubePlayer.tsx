import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { youtubeHostedPlayerUrl } from '../../lib/mediaUrl';

export type YouTubePlayerHandle = {
  play: () => void;
  pause: () => void;
  seek: (seconds: number) => void;
  getCurrentTime: () => number;
  getDuration: () => number;
  isPlaying: () => boolean;
};

type Props = {
  videoId: string;
  className?: string;
  onReady?: () => void;
  onError?: (code: number) => void;
  onTimeUpdate?: (time: number, duration: number, playing: boolean) => void;
};

type Snapshot = {
  time: number;
  duration: number;
  playing: boolean;
  state?: number;
};

/**
 * YouTube player via backend-hosted page (/api/media/youtube-player).
 * Real HTTPS origin on plink-backend avoids YouTube error 153 in Tauri/WebView.
 * Control via postMessage bridge (play/pause/seek/state).
 */
export const YouTubePlayer = forwardRef<YouTubePlayerHandle, Props>(function YouTubePlayer(
  { videoId, className, onReady, onError, onTimeUpdate },
  ref,
) {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const snapRef = useRef<Snapshot>({ time: 0, duration: 0, playing: false });
  const [lastError, setLastError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  const postCmd = useCallback((cmd: string, extra: Record<string, unknown> = {}) => {
    const win = iframeRef.current?.contentWindow;
    if (!win) return;
    win.postMessage({ target: 'plink-yt', cmd, ...extra }, '*');
  }, []);

  useImperativeHandle(ref, () => ({
    play: () => postCmd('play'),
    pause: () => postCmd('pause'),
    seek: (seconds: number) => postCmd('seek', { seconds }),
    getCurrentTime: () => snapRef.current.time,
    getDuration: () => snapRef.current.duration,
    isPlaying: () => snapRef.current.playing,
  }), [postCmd]);

  useEffect(() => {
    setReady(false);
    setLastError(null);
    snapRef.current = { time: 0, duration: 0, playing: false };

    function onMessage(event: MessageEvent) {
      const data = event.data;
      if (!data || data.source !== 'plink-yt') return;

      if (data.type === 'ready') {
        setReady(true);
        onReady?.();
      }
      if (data.type === 'error') {
        const code = Number(data.code ?? -1);
        const msg = code === 153
          ? 'YouTube 153 — видео недоступно для встраивания. Попробуйте другое.'
          : `YouTube error ${code}`;
        setLastError(msg);
        onError?.(code);
      }
      if (data.type === 'tick' || data.type === 'state' || data.type === 'snapshot' || data.type === 'ready') {
        const snap: Snapshot = {
          time: Number(data.time ?? 0),
          duration: Number(data.duration ?? 0),
          playing: Boolean(data.playing),
          state: data.state ?? data.ytState,
        };
        snapRef.current = snap;
        onTimeUpdate?.(snap.time, snap.duration, snap.playing);
      }
    }

    window.addEventListener('message', onMessage);
    return () => window.removeEventListener('message', onMessage);
  }, [videoId, onReady, onError, onTimeUpdate]);

  if (!/^[A-Za-z0-9_-]{6,20}$/.test(videoId)) {
    return <div className="player-placeholder">Invalid YouTube id</div>;
  }

  const src = youtubeHostedPlayerUrl(videoId);

  return (
    <div className={`youtube-player-wrap ${className ?? ''}`}>
      <iframe
        ref={iframeRef}
        className="player-iframe"
        title="YouTube"
        src={src}
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
        referrerPolicy="strict-origin-when-cross-origin"
        allowFullScreen
      />
      {!ready && !lastError && (
        <div className="youtube-player-loading">Загрузка плеера…</div>
      )}
      {lastError && <div className="youtube-player-error">{lastError}</div>}
    </div>
  );
});
