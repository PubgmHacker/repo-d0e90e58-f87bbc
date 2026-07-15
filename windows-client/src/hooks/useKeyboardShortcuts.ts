import { useEffect } from 'react';

type Handlers = {
  onSearch?: () => void;
  onNewRoom?: () => void;
  onJoin?: () => void;
  onTogglePlay?: () => void;
  onFullscreen?: () => void;
  onEscape?: () => void;
};

export function useKeyboardShortcuts(handlers: Handlers, enabled = true) {
  useEffect(() => {
    if (!enabled) return;

    const onKey = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === 'k') { e.preventDefault(); handlers.onSearch?.(); }
      if (mod && e.key.toLowerCase() === 'n') { e.preventDefault(); handlers.onNewRoom?.(); }
      if (mod && e.key.toLowerCase() === 'j') { e.preventDefault(); handlers.onJoin?.(); }
      if (e.key === ' ' && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) {
        e.preventDefault();
        handlers.onTogglePlay?.();
      }
      if (e.key.toLowerCase() === 'f') handlers.onFullscreen?.();
      if (e.key === 'Escape') handlers.onEscape?.();
    };

    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [enabled, handlers]);
}