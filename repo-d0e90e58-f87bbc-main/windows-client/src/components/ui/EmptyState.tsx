type Props = {
  icon?: string;
  title: string;
  description: string;
  ctaTitle?: string;
  onCta?: () => void;
};

export function EmptyState({ icon = '◎', title, description, ctaTitle, onCta }: Props) {
  return (
    <div className="empty-state-card glass-surface" role="status">
      <div className="empty-state-icon" aria-hidden>
        {icon}
      </div>
      <h3 className="empty-state-title">{title}</h3>
      <p className="empty-state-desc">{description}</p>
      {ctaTitle && onCta && (
        <button type="button" className="cinema-btn cinema-btn-light" onClick={onCta}>
          {ctaTitle}
        </button>
      )}
    </div>
  );
}
