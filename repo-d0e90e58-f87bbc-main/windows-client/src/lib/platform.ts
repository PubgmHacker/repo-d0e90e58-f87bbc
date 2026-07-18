/** Desktop platform hint — UI is identical on macOS and Windows. */
export type DesktopPlatform = 'mac' | 'win' | 'other';

export function detectPlatform(): DesktopPlatform {
  const p = (navigator.platform || '').toLowerCase();
  const ua = navigator.userAgent.toLowerCase();
  if (p.includes('mac') || ua.includes('macintosh')) return 'mac';
  if (p.includes('win') || ua.includes('windows')) return 'win';
  return 'other';
}