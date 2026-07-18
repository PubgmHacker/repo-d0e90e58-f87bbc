export type LiveTheme = {
  id: string;
  label: string;
  primary: string;
  secondary: string;
};

export const LIVE_THEMES: LiveTheme[] = [
  { id: 'cinema', label: 'Cinema', primary: '#5ab09b', secondary: '#d7a750' },
  { id: 'aurora', label: 'Aurora', primary: '#7c5cff', secondary: '#2de2e6' },
  { id: 'sunset', label: 'Sunset', primary: '#ff7b54', secondary: '#ffd166' },
  { id: 'ocean', label: 'Ocean', primary: '#2de2e6', secondary: '#488c7c' },
  { id: 'cosmos', label: 'Cosmos', primary: '#b47bff', secondary: '#6b4cff' },
  { id: 'verdant', label: 'Verdant', primary: '#58d68d', secondary: '#3d8b5e' },
];