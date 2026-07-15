type IconProps = { size?: number; className?: string };

const defaults = { size: 20, className: '' };

function stroke(props: IconProps) {
  const { size = 20, className = '' } = { ...defaults, ...props };
  return { width: size, height: size, className: `icon ${className}`.trim(), fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };
}

export function IconHome(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <path d="M3 10.5 12 3l9 7.5" />
      <path d="M5 9.5V20h14V9.5" />
    </svg>
  );
}

export function IconSearch(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </svg>
  );
}

export function IconRooms(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <rect x="2" y="5" width="20" height="14" rx="2" />
      <path d="M8 21V5" />
    </svg>
  );
}

export function IconFriends(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <circle cx="9" cy="8" r="3" />
      <circle cx="17" cy="10" r="2.5" />
      <path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6" />
      <path d="M14 20c0-2.2 1.5-4 3.5-4.5" />
    </svg>
  );
}

export function IconChat(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <path d="M4 5h16v10H8l-4 4z" />
    </svg>
  );
}

export function IconAi(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <path d="M12 3v3" />
      <path d="M12 18v3" />
      <path d="M3 12h3" />
      <path d="M18 12h3" />
      <circle cx="12" cy="12" r="4" />
    </svg>
  );
}

export function IconSettings(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  );
}

export function IconUser(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <circle cx="12" cy="8" r="4" />
      <path d="M4 20c0-4 3.6-7 8-7s8 3 8 7" />
    </svg>
  );
}

export function IconPlus(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24">
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

export function IconPlay(p: IconProps) {
  const s = stroke(p);
  return (
    <svg {...s} viewBox="0 0 24 24" fill="currentColor" stroke="none">
      <path d="M8 5v14l11-7z" />
    </svg>
  );
}