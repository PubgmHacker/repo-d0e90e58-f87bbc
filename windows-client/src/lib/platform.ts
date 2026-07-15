export type DesktopPlatform = 'mac' | 'win' | 'other';

export function detectPlatform(): DesktopPlatform {
  const p = (navigator.platform || '').toLowerCase();
  const ua = navigator.userAgent.toLowerCase();
  if (p.includes('mac') || ua.includes('macintosh')) return 'mac';
  if (p.includes('win') || ua.includes('windows')) return 'win';
  return 'other';
}

export function initPlatformClass() {
  const root = document.documentElement;
  root.classList.remove('platform-mac', 'platform-win', 'platform-other');
  const plat = detectPlatform();
  root.classList.add(plat === 'mac' ? 'platform-mac' : plat === 'win' ? 'platform-win' : 'platform-other');
  return plat;
}