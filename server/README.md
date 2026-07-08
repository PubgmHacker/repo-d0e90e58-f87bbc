# Plink Backend Security — Этап 1

## Что включено

3 файла для копирования в backend-репозиторий:

### 1. `src/middleware/security.ts` — Security middleware
- **3.1** `isRoomHost()` + `requireHost()` — проверка что только хост может play/pause/seek
- **3.3** `sanitizeChatMessage()` — перезаписывает senderID/senderName из JWT, санитизирует текст
- **3.5** `hashRoomPassword()` / `verifyRoomPassword()` — bcrypt хеширование паролей комнат
- Rate limiting для WS команд (10/sec per user)
- Текст санитизация: HTML strip + 150 char limit + control char removal

### 2. `src/websocket/ws-handler-secure.ts` — Обновлённый WS handler
- senderID/senderName берутся из `socket.user` (JWT), НЕ из client payload
- play/pause/seek проверяются через `isRoomHost()`
- Chat текст санитизируется через `sanitizeChatMessage()`
- Rate limiting на все команды

### 3. `src/routes/rooms-secure.ts` — Обновлённые REST routes
- Пароль хешируется при создании комнаты (`hashRoomPassword`)
- Пароль проверяется при входе (`verifyRoomPassword`)
- Пароль НИКОГДА не возвращается в API ответе
- `/rooms` возвращает только `privacy: 'public'` комнаты
- `/rooms/:id/playback` защищён `requireHost` preHandler

## Установка

```bash
# В backend-репозитории:
npm install bcrypt

# Копировать файлы:
cp server/src/middleware/security.ts    → backend/src/middleware/security.ts
cp server/src/websocket/ws-handler-secure.ts → backend/src/websocket/ws-handler.ts
cp server/src/routes/rooms-secure.ts    → backend/src/routes/rooms.ts
```

## Интеграция

### В `src/index.ts`:
```typescript
import { setupWebSocketHandler } from './websocket/ws-handler.js';
import roomRoutes from './routes/rooms.js';

// WebSocket
setupWebSocketHandler(io, prisma, fastify);

// Routes
fastify.register(roomRoutes, { prefix: '/api' });
```

### В Prisma schema (`schema.prisma`):
```prisma
model Room {
  // ... existing fields ...
  password    String?   // ← хранит bcrypt hash, nullable
  privacy     String    @default("public") // public | private | link
}
```

## Что меняется

| До | После |
|----|-------|
| Зритель может отправить play/pause/seek | ❌ Только хост (server-side check) |
| Client отправляет senderID в chat | ❌ Server перезаписывает из JWT |
| Пароль хранится в plaintext | ❌ bcrypt hash |
| Все комнаты видны в /rooms | ❌ Только public |
| Пароль возвращается в API | ❌ Никогда |
| Нет rate limiting | ✅ 10 команд/sec max |
| Нет санитизации текста | ✅ HTML strip + 150 char + control chars |
