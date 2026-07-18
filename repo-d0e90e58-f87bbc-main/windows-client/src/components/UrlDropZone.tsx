import type { DragEvent, ReactNode } from 'react';

type Props = {
  children: ReactNode;
  onUrl: (url: string) => void;
};

const URL_PATTERN = /youtube\.com|rutube\.ru|vk\.com|youtu\.be/;

export function UrlDropZone({ children, onUrl }: Props) {
  function handleDrop(e: DragEvent) {
    e.preventDefault();
    const text = e.dataTransfer.getData('text/plain') || e.dataTransfer.getData('text/uri-list');
    if (text && URL_PATTERN.test(text)) onUrl(text.trim());
  }

  return (
    <div onDrop={handleDrop} onDragOver={(e) => e.preventDefault()} className="url-drop-root">
      {children}
    </div>
  );
}