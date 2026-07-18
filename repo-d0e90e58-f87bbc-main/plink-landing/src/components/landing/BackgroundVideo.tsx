'use client';

import { useEffect } from 'react';
import { LivingBackdrop } from './LivingBackdrop';

export function BackgroundVideo() {
  useEffect(() => {
    const video = document.getElementById('plink-bg-video') as HTMLVideoElement | null;
    if (!video) return;

    const tryPlay = () => {
      if (document.visibilityState !== 'visible') return;
      video.play().catch(() => undefined);
    };

    document.addEventListener('visibilitychange', tryPlay);
    window.addEventListener('focus', tryPlay);
    tryPlay();
    return () => {
      document.removeEventListener('visibilitychange', tryPlay);
      window.removeEventListener('focus', tryPlay);
    };
  }, []);

  return (
    <div className="rave-bg" aria-hidden>
      <video
        id="plink-bg-video"
        className="rave-bg__video"
        autoPlay
        muted
        loop
        playsInline
        poster="/img/plink-home.jpg"
      >
        <source src="https://cdn.saverave.com/video/bg.webm" type="video/webm" />
        <source src="https://cdn.saverave.com/video/bgvideo.mp4" type="video/mp4" />
      </video>
      <LivingBackdrop animateThemes />
      <div className="rave-bg__overlay" />
      <div className="rave-bg__grain" />
    </div>
  );
}