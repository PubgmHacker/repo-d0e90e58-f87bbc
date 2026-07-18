export type RoomState = {
  protocolVersion: 2;
  roomId: string;
  epoch: number;
  seq: number;
  mediaId: string | null;
  positionMs: number;
  playing: boolean;
  rate: number;
  effectiveAtServerMs: number;
  issuedBy: string;
};

export type SyncStateMessage = {
  type: 'sync.state';
  state: RoomState;
  serverTimeMs: number;
};

export type SessionReadyMessage = {
  type: 'session.ready';
  roomId: string;
  role: 'host' | 'viewer';
  serverTimeMs: number;
};