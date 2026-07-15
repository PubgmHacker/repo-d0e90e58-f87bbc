import { api } from './api';
import type { ChatMessage } from './types';

const WS_BASE = import.meta.env.VITE_WS_BASE ?? 'wss://plink-backend-production-ef31.up.railway.app';

export type RealtimeHandlers = {
  onMessage?: (msg: ChatMessage) => void;
  onParticipantJoined?: (userId: string, username: string) => void;
  onParticipantLeft?: (userId: string) => void;
  onStateChange?: (connected: boolean) => void;
  onError?: (error: string) => void;
};

export class PlinkRealtimeClient {
  private socket: WebSocket | null = null;
  private roomId: string | null = null;
  private handlers: RealtimeHandlers;

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

    this.socket.onopen = () => this.handlers.onStateChange?.(true);
    this.socket.onclose = () => this.handlers.onStateChange?.(false);
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
    this.socket?.close();
    this.socket = null;
    this.roomId = null;
  }

  sendChat(text: string) {
    if (!this.socket || !this.roomId || this.socket.readyState !== WebSocket.OPEN) return;
    const payload = {
      type: 'chat.send',
      protocolVersion: 2,
      roomId: this.roomId,
      clientMessageId: crypto.randomUUID(),
      text,
    };
    this.socket.send(JSON.stringify(payload));
  }

  private handleServerMessage(data: Record<string, unknown>) {
    switch (data.type) {
      case 'chat.broadcast':
        this.handlers.onMessage?.({
          id: String(data.messageId),
          senderID: String(data.senderId ?? data.senderID ?? ''),
          text: String(data.text ?? ''),
          createdAt: new Date(Number(data.timestampMs ?? Date.now())).toISOString(),
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
      case 'error':
        this.handlers.onError?.(String(data.message ?? data.code ?? 'Realtime error'));
        break;
      default:
        break;
    }
  }
}