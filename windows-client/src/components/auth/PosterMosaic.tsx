/** Full-quality reference banner — no CSS hacks */
export function PosterMosaic() {
  return (
    <div className="auth-banner-panel" aria-hidden>
      <img src="/auth-banner.jpg" alt="" className="auth-banner-img" draggable={false} />
    </div>
  );
}