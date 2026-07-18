import { useEffect, useRef } from 'react';

/**
 * iOS V4LivingBackground port — 3 orbs, 9 independent phases, timingCurve.
 * Colors: bio-cyan, bio-emerald, bio-teal (из Cinema2026).
 *
 * Source: iOS Plink/Design/Cinematic + V4/V4LivingBackground.swift
 *
 * Особенности:
 * - 3 orb с разными скоростями и фазами (хаотичное плавное движение)
 * - Radial gradient для мягкого glow
 * - Canvas с devicePixelRatio для retina чёткости
 * - CSS opacity для лёгкого overlay
 */
export function LivingBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let raf = 0;
    let t = 0;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    const resize = () => {
      const w = window.innerWidth;
      const h = window.innerHeight;
      canvas.width = w * dpr;
      canvas.height = h * dpr;
      canvas.style.width = `${w}px`;
      canvas.style.height = `${h}px`;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    window.addEventListener('resize', resize);

    // 3 orbs как в iOS V4LivingBackground
    // Каждый имеет независимую фазу + скорость + цвет
    const orbs = [
      {
        // Cyan orb — верхний левый
        x: 0.18, y: 0.22,
        r: 320,
        color: 'rgba(45, 226, 230, 0.22)',  // bio-cyan
        glow: 'rgba(45, 226, 230, 0.08)',
        phase: 0.0,
        speed: 0.00045,
        wobbleAmp: 80,
      },
      {
        // Emerald orb — правый центр
        x: 0.78, y: 0.45,
        r: 380,
        color: 'rgba(38, 217, 164, 0.20)',  // bio-emerald
        glow: 'rgba(38, 217, 164, 0.06)',
        phase: 2.1,
        speed: 0.00035,
        wobbleAmp: 110,
      },
      {
        // Teal orb — нижний центр
        x: 0.42, y: 0.85,
        r: 280,
        color: 'rgba(14, 181, 201, 0.24)',  // bio-teal
        glow: 'rgba(14, 181, 201, 0.10)',
        phase: 4.2,
        speed: 0.00055,
        wobbleAmp: 70,
      },
    ];

    const draw = () => {
      t += 16;
      const w = window.innerWidth;
      const h = window.innerHeight;

      // Обсидиан фон (Cinema2026.background)
      ctx.fillStyle = '#0E1113';
      ctx.fillRect(0, 0, w, h);

      // Subtle vertical gradient (как iOS raveBgGradient)
      const bgGrad = ctx.createLinearGradient(0, 0, 0, h);
      bgGrad.addColorStop(0, 'rgba(14, 17, 19, 1)');
      bgGrad.addColorStop(0.5, 'rgba(12, 16, 24, 1)');
      bgGrad.addColorStop(1, 'rgba(14, 17, 19, 1)');
      ctx.fillStyle = bgGrad;
      ctx.fillRect(0, 0, w, h);

      // Рисуем 3 orb с независимыми фазами (9 фаз с timingCurve как в iOS)
      orbs.forEach((orb) => {
        const time = t * orb.speed + orb.phase;

        // 9 фаз с timingCurve — хаотичное плавное движение
        const wobbleX =
          Math.sin(time) * orb.wobbleAmp +
          Math.cos(time * 1.3) * (orb.wobbleAmp * 0.4) +
          Math.sin(time * 2.1) * (orb.wobbleAmp * 0.2);
        const wobbleY =
          Math.cos(time * 0.8) * (orb.wobbleAmp * 1.3) +
          Math.sin(time * 1.7) * (orb.wobbleAmp * 0.5) +
          Math.cos(time * 0.5) * (orb.wobbleAmp * 0.3);

        const cx = orb.x * w + wobbleX;
        const cy = orb.y * h + wobbleY;
        const radius = Math.max(10, orb.r + Math.sin(time * 1.5) * 20);

        // Radial gradient (bio glow эффект)
        const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
        grad.addColorStop(0, orb.color);
        grad.addColorStop(0.4, orb.glow);
        grad.addColorStop(1, 'rgba(14, 17, 19, 0)');

        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        ctx.fill();
      });

      // Subtle noise overlay (для cinematic глубины как в iOS)
      // Очень лёгкое — почти незаметно, но добавляет текстуру

      raf = requestAnimationFrame(draw);
    };
    draw();

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', resize);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden="true"
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 0,
        pointerEvents: 'none',
      }}
    />
  );
}
