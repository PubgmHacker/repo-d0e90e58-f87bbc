export function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI__' in window;
}

export async function setupTrayListener(callback: (action: string) => void) {
  if (!isTauri()) return () => {};
  const { listen } = await import('@tauri-apps/api/event');
  const unlisten = await listen<string>('menu-action', (event) => {
    callback(event.payload);
  });
  return unlisten;
}

export async function showNotification(title: string, body: string) {
  if (!isTauri()) {
    if ('Notification' in window && Notification.permission === 'granted') {
      new Notification(title, { body });
    }
    return;
  }
  const { sendNotification, isPermissionGranted, requestPermission } = await import(
    '@tauri-apps/api/notification'
  );
  if (!(await isPermissionGranted())) {
    await requestPermission();
  }
  sendNotification({ title, body });
}

export async function hideToTray() {
  if (!isTauri()) return;
  const { appWindow } = await import('@tauri-apps/api/window');
  await appWindow.hide();
}