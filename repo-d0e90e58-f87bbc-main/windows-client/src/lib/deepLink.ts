import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { isTauri } from './tauri';

// ════════════════════════════════════════════════════════════════════
// Deep Link Handler for Tauri desktop
// Supports: plink://room/CODE, plink://r/CODE, https://plink.app/r/CODE
// ════════════════════════════════════════════════════════════════════

export interface DeepLinkHandler {
  onRoomCode: (code: string) => void;
  onUserInvite?: (userId: string) => void;
}

let unlisten: UnlistenFn | undefined;

export async function setupDeepLinks(handler: DeepLinkHandler): Promise<void> {
  if (!isTauri()) {
    // Web fallback: handle plink:// URLs via window.location
    handleWebDeepLink(handler);
    return;
  }

  // Tauri: listen for deep-link events
  unlisten = await listen<string>('deep-link', (event) => {
    const url = event.payload as string;
    handleDeepLinkUrl(url, handler);
  });

  // Also handle initial URL if app was opened via link
  try {
    // Tauri 1.x: deep-link plugin provides initial URL via event
    // (initial URL handled by same listener)
  } catch (e) {
    console.warn('[deepLink] Failed to get initial URL:', e);
  }
}

export function teardownDeepLinks() {
  unlisten?.();
  unlisten = undefined;
}

function handleDeepLinkUrl(url: string, handler: DeepLinkHandler) {
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();
    const segments = parsed.pathname.split('/').filter(Boolean);

    // plink://room/CODE → host=room, path=/CODE
    // plink://r/CODE → host=r, path=/CODE
    // https://plink.app/r/CODE → host=plink.app, path=/r/CODE
    let code: string | undefined;

    if (host === 'room' || host === 'r') {
      code = segments[0];
    } else if (segments.length >= 2 && (segments[0] === 'room' || segments[0] === 'r')) {
      code = segments[1];
    } else if (segments.length === 1 && /^[A-Z0-9]{4,8}$/i.test(segments[0])) {
      code = segments[0];
    } else {
      code = parsed.searchParams.get('code') ?? undefined;
    }

    if (code) {
      console.log(`[deepLink] Room code: ${code}`);
      handler.onRoomCode(code.toUpperCase());
      // Analytics: log deep link open
      import('./analytics').then(({ analytics }) => analytics.roomJoined()).catch(() => {});
    }

    // Friend invite: plink://u/<userId>
    if (host === 'u' && segments[0]) {
      handler.onUserInvite?.(segments[0]);
    }
  } catch (e) {
    console.warn('[deepLink] Failed to parse URL:', url, e);
  }
}

function handleWebDeepLink(handler: DeepLinkHandler) {
  // In browser, listen for hash changes (e.g. #/room/CODE)
  function checkHash() {
    const hash = window.location.hash;
    const match = hash.match(/^#\/(?:room|r)\/([A-Z0-9]{4,8})$/i);
    if (match) {
      handler.onRoomCode(match[1].toUpperCase());
    }
  }

  checkHash();
  window.addEventListener('hashchange', checkHash);
}

// ════════════════════════════════════════════════════════════════════
// Tauri config additions (add to tauri.conf.json):
// ════════════════════════════════════════════════════════════════════
//
// Add to tauri.allowlist:
//   "deepLink": {
//     "all": true,
//     "domains": ["plink.app"]
//   }
//
// Add to tauri bundle.macOS (for protocol registration):
//   "macOS": {
//     "signingIdentity": null,
//     "entitlements": null
//   }
//
// Register protocol scheme (Info.plist on macOS, registry on Windows):
// macOS — Info.plist:
//   <key>CFBundleURLTypes</key>
//   <array>
//     <dict>
//       <key>CFBundleURLName</key>
//       <string>com.plink.desktop</string>
//       <key>CFBundleURLSchemes</key>
//       <array><string>plink</string></array>
//     </dict>
//   </array>
//
// Windows — tauri.conf.json bundle.windows:
//   "windows": {
//     "webviewInstallMode": { "type": "downloadBootstrapper" }
//   }
//   + nsis installer registers: HKCU\Software\Classes\plink\shell\open\command
