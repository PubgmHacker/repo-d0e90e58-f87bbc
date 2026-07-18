/** Lightweight analytics for desktop MVP (console + optional beacon). */

type Props = Record<string, string | number | boolean | undefined>;

const ENDPOINT = import.meta.env.VITE_ANALYTICS_URL as string | undefined;

export function track(event: string, props: Props = {}) {
  const payload = {
    event,
    props: { ...props, platform: 'desktop', ts: Date.now() },
  };
  if (import.meta.env.DEV) {
    // eslint-disable-next-line no-console
    console.info('[Analytics]', payload);
  }
  try {
    if (ENDPOINT) {
      void fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        keepalive: true,
      });
    }
  } catch {
    /* ignore */
  }
}

export const analytics = {
  appOpen: () => track('app_open'),
  login: () => track('login'),
  signUp: () => track('sign_up'),
  roomCreated: () => track('room_created'),
  roomJoined: () => track('room_joined'),
  messageSent: () => track('message_sent'),
  aiChat: () => track('ai_chat_used'),
  syncDrift: (ms: number) => track('sync_drift', { drift_ms: ms }),
};
