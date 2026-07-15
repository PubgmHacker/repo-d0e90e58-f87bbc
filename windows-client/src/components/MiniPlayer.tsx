type Props = {
  title: string;
  embedUrl: string;
  onClose: () => void;
  onExpand: () => void;
};

export function MiniPlayer({ title, embedUrl, onClose, onExpand }: Props) {
  return (
    <div className="mini-player" role="dialog" aria-label="Mini player">
      <div className="mini-player-header">
        <span>{title}</span>
        <div>
          <button type="button" onClick={onExpand} title="Expand">⛶</button>
          <button type="button" onClick={onClose} title="Close">×</button>
        </div>
      </div>
      <iframe title={title} src={embedUrl} allow="autoplay; encrypted-media" />
    </div>
  );
}