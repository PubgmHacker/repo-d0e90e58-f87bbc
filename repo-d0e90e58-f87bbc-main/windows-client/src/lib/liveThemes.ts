export type LiveTheme = {
  id: string;
  label: string;
  primary: string;
  secondary: string;
};

/** Mirrors iOS RoomTheme + Plink+ live theme accents */
export const LIVE_THEMES: LiveTheme[] = [
  { id: 'default', label: 'Cinema', primary: '#5ab09b', secondary: '#d7a750' },
  { id: 'neon', label: 'Neon Night', primary: '#a970ff', secondary: '#2de2e6' },
  { id: 'sunset', label: 'Sunset', primary: '#e87850', secondary: '#d7a750' },
  { id: 'ocean', label: 'Ocean', primary: '#2de2e6', secondary: '#488c7c' },
  { id: 'galaxy', label: 'Galaxy', primary: '#b47bff', secondary: '#6b4cff' },
  { id: 'forest', label: 'Forest', primary: '#58d68d', secondary: '#3d8b5e' },
];

export function themeByIndex(i: number): LiveTheme {
  return LIVE_THEMES[i % LIVE_THEMES.length]!;
}