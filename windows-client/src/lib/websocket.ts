import { api } from './api';
import type { ChatMessage } from './types';
import type { RoomState, SessionReadyMessage, SyncStateMessage } from './syncTypes';

const WS_BASE = import.meta.env.VITE_WS_BASE ?? 'wss://plink-backend-production-ef31.up.railway.app';

export type RealtimeHandlers = {
  onMessage?: (msg: ChatMessage) => void;
  onParticipantJoined?: (userId: string, username: string) => void;
  onParticipantLeft?: (userId: string) => void;
  onStateChange?: (connected: boolean) => void;
  onError?: (error: string) => void;
  onSessionReady?: (msg: SessionReadyMessage) => void;
  onSyncState?: (state: RoomState, serverTimeMs: number) => void;
  onClockProbeReply?: (clientSentMs: number, serverMs: number) => void;
};

export class PlinkRealtimeClient {
  private socket: WebSocket | null = null;
  private roomId: string | null = null;
  private handlers: RealtimeHandlers;
  private probeTimer: number | null = null;

  constructor(handlers: RealtimeHandlers = {}) {
    this.handlers = handlers;
  }

  async connect(roomId: string) {
    this.disconnect();
    this.roomId = roomId;

    const { ticket, protocol } = await api.getRealtimeTicket(roomId);
    const url = `${WS_BASE}/ws/room/${roomId}`;
    const subprotocols = protocol.length ? protocol : ['plink.v2', `plink.ticket.${ticket}`];

    this.socket = new WebSocket(url, subprotocols);

    this.socket.onopen = () => {
      this.handlers.onStateChange?.(true);
      this.requestState();
      this.startClockProbes();
    };
    this.socket.onclose = () => {
      this.handlers.onStateChange?.(false);
      this.stopClockProbes();
    };
    this.socket.onerror = () => this.handlers.onError?.('WebSocket connection failed');

    this.socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data as string);
        this.handleServerMessage(data);
      } catch {
        this.handlers.onError?.('Invalid WebSocket message');
      }
    };
  }

  disconnect() {
    this.stopClockProbes();
    this.socket?.close();
    this.socket = null;
    this.roomId = null;
  }

  private startClockProbes() {
    this.stopClockProbes();
    const probe = () => {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
      this.socket.send(JSON.stringify({
        type: 'clock.probe',
        protocolVersion: 2,
        clientSentMs: Date.now(),
      }));
    };
    probe();
    this.probeTimer = window.setInterval(probe, 5000);
  }

  private stopClockProbes() {
    if (this.probeTimer != null) {
      window.clearInterval(this.probeTimer);
      this.probeTimer = null;
    }
  }

  sendChat(text: string) {
    if (!this.socket || !this.roomId || this.socket.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify({
      type: 'chat.send',
      protocolVersion: 2,
      roomId: this.roomId,
      clientMessageId: crypto.randomUUID(),
      text,
    }));
  }

  requestState() {
    if (!this.socket || !this.roomId || this.socket.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify({
      type: 'sync.state.request',
      protocolVersion: 2,
      roomId: this.roomId,
      afterSeq: 0,
    }));
  }

  /** Host-only: push playback intent. */
  sendSyncCommand(opts: {
    mediaId: string | null;
    positionMs: number;
    playing: boolean;
    rate?: number;
  }) {
    if (!this.socket || !this.roomId || this.socket.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify({
      type: 'sync.command',
      protocolVersion: 2,
      roomId: this.roomId,
      actionId: crypto.randomUUID(),
      mediaId: opts.mediaId,
      positionMs: Math.max(0, Math.round(opts.positionMs)),
      playing: opts.playing,
      rate: opts.rate ?? 1,
    }));
  }

  private handleServerMessage(data: Record<string, unknown>) {
    switch (data.type) {
      case 'session.ready':
        this.handlers.onSessionReady?.(data as unknown as SessionReadyMessage);
        break;
      case 'chat.broadcast':
        this.handlers.onMessage?.({
          id: String(data.messageId),
          senderID: String(data.senderId ?? data.senderID ?? ''),
          text: String(data.text ?? ''),
          createdAt: new Date(Number(data.createdAtMs ?? data.timestampMs ?? Date.now())).toISOString(),
          clientMessageId: data.clientMessageId as string | undefined,
        });
        break;
      case 'participant.joined':
        this.handlers.onParticipantJoined?.(
          String(data.userId),
          String(data.username ?? 'User'),
        );
        break;
      case 'participant.left':
        this.handlers.onParticipantLeft?.(String(data.userId));
        break;
      case 'sync.state':
      case 'sync.state.snapshot': {
        const state = data.state as RoomState | null;
        if (state) {
          this.handlers.onSyncState?.(state, Number(data.serverTimeMs ?? Date.now()));
        }
        break;
      }
      case 'clock.probe.reply':
        this.handlers.onClockProbeReply?.(
          Number(data.clientSentMs),
          Number(data.serverMs),
        );
        break;
      case 'error':
        this.handlers.onError?.(String(data.message ?? data.code ?? 'Realtime error'));
        break;
      default:
        break;
    }
  }
}

// re-export types used by RoomPage
export type { SyncStateMessage };
