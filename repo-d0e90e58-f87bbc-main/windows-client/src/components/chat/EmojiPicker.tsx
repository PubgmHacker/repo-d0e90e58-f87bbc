import { useState, useEffect, useRef } from 'react';
import { ALL_PACKS, type EmojiItem } from '../../lib/emojiManifest';

interface Props {
  isPremium: boolean;
  onPick: (emoji: EmojiItem) => void;
  onClose: () => void;
}

/**
 * Telegram-style emoji picker.
 * - Tabs сверху (free + 5 premium packs)
 * - Grid 8xN с emoji
 * - Premium lock 🔒 на packs для non-premium users
 * - Click → onPick(emoji)
 *
 * Source: iOS PlinkEmojiManifest + Telegram emoji picker UX
 */
export function EmojiPicker({ isPremium, onPick, onClose }: Props) {
  const [activePack, setActivePack] = useState('free');
  const pickerRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (pickerRef.current && !pickerRef.current.contains(e.target as Node)) {
        onClose();
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  const current = ALL_PACKS.find((p) => p.id === activePack) ?? ALL_PACKS[0];

  return (
    <div className="emoji-picker" ref={pickerRef}>
      {/* Tabs — pack selector */}
      <div className="emoji-tabs">
        {ALL_PACKS.map((pack) => {
          const locked = pack.premium && !isPremium;
          return (
            <button
              key={pack.id}
              type="button"
              className={`emoji-tab ${activePack === pack.id ? 'active' : ''} ${pack.premium ? 'premium' : ''} ${locked ? 'locked' : ''}`}
              onClick={() => {
                if (locked) return;
                setActivePack(pack.id);
              }}
              title={locked ? `${pack.name} (Plink+)` : pack.name}
            >
              {pack.icon ? (
                <img src={pack.icon} alt={pack.name} />
              ) : (
                <span className="emoji-tab-icon">😀</span>
              )}
              {pack.premium && <span className="premium-lock">🔒</span>}
            </button>
          );
        })}
      </div>

      {/* Grid */}
      <div className="emoji-grid">
        {current.emojis.map((emoji) => (
          <button
            key={emoji.id}
            type="button"
            className="emoji-item"
            onClick={() => onPick(emoji)}
            title={emoji.name}
          >
            {emoji.src ? (
              <img src={emoji.src} alt={emoji.name} />
            ) : (
              <span>{emoji.id}</span>
            )}
          </button>
        ))}
      </div>

      {/* Footer — pack name + count */}
      <div className="emoji-footer">
        <span className="emoji-pack-name">{current.name}</span>
        <span className="emoji-count">{current.emojis.length} emojis</span>
        {current.premium && !isPremium && (
          <span className="emoji-upgrade">Plink+ required</span>
        )}
      </div>
    </div>
  );
}
