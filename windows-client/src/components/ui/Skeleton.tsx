export function Skeleton({ className = '' }: { className?: string }) {
  return <div className={`skeleton ${className}`.trim()} aria-hidden />;
}

export function HomeSkeleton() {
  return (
    <div className="pro-home skeleton-home">
      <Skeleton className="sk-search" />
      <Skeleton className="sk-hero" />
      <div className="pro-columns">
        {[0, 1, 2].map((i) => (
          <div key={i} className="pro-column glass-panel">
            <Skeleton className="sk-title" />
            <div className="sk-grid">
              {[0, 1, 2, 3].map((j) => (
                <Skeleton key={j} className="sk-card" />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}