export function Skeleton({ className = '' }: { className?: string }) {
  return <div className={`skeleton ${className}`.trim()} aria-hidden />;
}

export function HomeSkeleton() {
  return (
    <div className="cinema-home skeleton-home">
      <Skeleton className="sk-hero-netflix" />
      <Skeleton className="sk-ai-card" />
      <Skeleton className="sk-rail-title" />
      <div className="sk-rail-row">
        {[0, 1, 2, 3, 4].map((i) => (
          <Skeleton key={i} className="sk-poster" />
        ))}
      </div>
    </div>
  );
}