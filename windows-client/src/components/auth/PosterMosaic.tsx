/* iOS AnimatedPosterMosaic — same TMDB poster URLs */
const POSTERS = [
  'https://image.tmdb.org/t/p/w500/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg',
  'https://image.tmdb.org/t/p/w500/qNBAXBIQlnOThrVvA6mA2B5ggV6.jpg',
  'https://image.tmdb.org/t/p/w500/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg',
  'https://image.tmdb.org/t/p/w500/aDQZHvI3rGdtzZ2nFGzJXWL7X5m.jpg',
  'https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7clRv7wq.jpg',
  'https://image.tmdb.org/t/p/w500/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg',
  'https://image.tmdb.org/t/p/w500/9gk7adHYeDvHkCSEqAvQNLV5Uge.jpg',
  'https://image.tmdb.org/t/p/w500/b41qXmtBtZQ3hU2rL3mJ8mFnFk.jpg',
  'https://image.tmdb.org/t/p/w500/7Hfi13FfRTIfEYFiQXiIuV2xV8a.jpg',
];

function Column({ start, offset }: { start: number; offset?: boolean }) {
  const items = [0, 1, 2].map((i) => POSTERS[(start + i) % POSTERS.length]);
  return (
    <div className={`mosaic-col ${offset ? 'mosaic-col-offset' : ''}`}>
      {items.map((url, i) => (
        <div key={`${start}-${i}`} className="mosaic-poster">
          <img src={url} alt="" loading="lazy" />
        </div>
      ))}
    </div>
  );
}

export function PosterMosaic() {
  return (
    <div className="poster-mosaic">
      <div className="mosaic-glow" aria-hidden />
      <div className="mosaic-grid">
        <Column start={0} />
        <Column start={3} offset />
        <Column start={6} />
      </div>
      <div className="mosaic-fade" aria-hidden />
      <div className="mosaic-tagline">
        <p className="mosaic-eyebrow">PLINK</p>
        <h2>Смотрите вместе</h2>
        <p>Your stories. Your time. Together.</p>
      </div>
    </div>
  );
}