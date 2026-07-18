type Props = {
  src: string;
  title: string;
  className?: string;
};

/** Generic iframe embed for VK / Rutube / external (not YouTube — use YouTubePlayer). */
export function EmbedPlayer({ src, title, className }: Props) {
  return (
    <iframe
      className={`player-iframe ${className ?? ''}`}
      title={title}
      src={src}
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
      referrerPolicy="strict-origin-when-cross-origin"
      allowFullScreen
    />
  );
}
