// src/middleware/security.ts — Pack 4: helmet-style security headers + 2FA
import bcrypt from 'bcryptjs';
import { prisma } from '../config/db.js';

// ═══════════════════════════════════════════════════════════════════════
// SECURITY HEADERS (helmet-equivalent)
// ═══════════════════════════════════════════════════════════════════════

export async function securityHeaders(request: any, reply: any) {
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('X-Frame-Options', 'DENY');
  reply.header('X-XSS-Protection', '1; mode=block');
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  reply.header('Permissions-Policy', 
    'geolocation=(), microphone=(), camera=(), payment=(), usb=()');
  reply.header('Strict-Transport-Security', 
    'max-age=31536000; includeSubDomains; preload');
  reply.header('Content-Security-Policy', 
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
    "img-src 'self' data: https:; media-src 'self' https:; " +
    "connect-src 'self' wss: https:;");
  reply.header('Cross-Origin-Opener-Policy', 'same-origin');
  reply.header('Cross-Origin-Embedder-Policy', 'require-corp');
  reply.header('Cross-Origin-Resource-Policy', 'same-origin');
}

// ═══════════════════════════════════════════════════════════════════════
// 2FA — TOTP (Time-based One-Time Password)
// ═══════════════════════════════════════════════════════════════════════

import crypto from 'crypto';

const BASE32_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buffer: Buffer): string {
  let result = '';
  let bits = 0;
  let value = 0;
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      result += BASE32_CHARS[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    result += BASE32_CHARS[(value << (5 - bits)) & 31];
  }
  return result;
}

function base32Decode(str: string): Buffer {
  str = str.toUpperCase().replace(/[^A-Z2-7]/g, '');
  const bytes: number[] = [];
  let buffer = 0;
  let bitsLeft = 0;
  for (const c of str) {
    const val = BASE32_CHARS.indexOf(c);
    if (val < 0) continue;
    buffer = (buffer << 5) | val;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bytes.push((buffer >> (bitsLeft - 8)) & 0xff);
      bitsLeft -= 8;
    }
  }
  return Buffer.from(bytes);
}

/** Генерация нового TOTP секрета для пользователя */
export function generateTOTPSecret(): string {
  const buffer = crypto.randomBytes(20);
  return base32Encode(buffer);
}

/** Генерация otpauth URL для QR-кода */
export function generateOTPAuthURL(secret: string, email: string, issuer = 'Plink'): string {
  const label = encodeURIComponent(`${issuer}:${email}`);
  const params = new URLSearchParams({
    secret,
    issuer,
    algorithm: 'SHA1',
    digits: '6',
    period: '30',
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

/** Генерация текущего TOTP кода */
export function generateTOTPCode(secret: string, timestamp = Date.now()): string {
  const buffer = base32Decode(secret);
  const counter = Math.floor(timestamp / 1000 / 30);
  const counterBuffer = Buffer.alloc(8);
  counterBuffer.writeBigInt64BE(BigInt(counter));
  
  const hmac = crypto.createHmac('sha1', buffer).update(counterBuffer).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code = ((hmac[offset] & 0x7f) << 24 |
                (hmac[offset + 1] & 0xff) << 16 |
                (hmac[offset + 2] & 0xff) << 8 |
                (hmac[offset + 3] & 0xff)) % 1000000;
  return code.toString().padStart(6, '0');
}

/** Проверка TOTP кода (с окном ±1 step для рассинхрона часов) */
export function verifyTOTP(secret: string, code: string): boolean {
  const now = Date.now();
  for (const offset of [-30000, 0, 30000]) {
    const expected = generateTOTPCode(secret, now + offset);
    if (crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(code))) {
      return true;
    }
  }
  return false;
}

/** Backup codes (8 штук, по 8 символов) */
export function generateBackupCodes(): string[] {
  return Array.from({ length: 8 }, () => 
    crypto.randomBytes(4).toString('hex').toUpperCase()
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Утилиты безопасности
// ═══════════════════════════════════════════════════════════════════════

/** Проверка пароля на сложность */
export function validatePasswordStrength(password: string): {
  valid: boolean;
  score: number;
  feedback: string[];
} {
  const feedback: string[] = [];
  let score = 0;
  
  if (password.length >= 8) score++;
  else feedback.push('Минимум 8 символов');
  
  if (password.length >= 12) score++;
  
  if (/[a-z]/.test(password) && /[A-Z]/.test(password)) score++;
  else feedback.push('Нужны заглавные и строчные буквы');
  
  if (/\d/.test(password)) score++;
  else feedback.push('Нужны цифры');
  
  if (/[^a-zA-Z\d]/.test(password)) score++;
  else feedback.push('Нужны спецсимволы');
  
  // Проверка на часто используемые пароли
  const common = ['password', '123456', 'qwerty', 'admin', 'letmein'];
  if (common.some(p => password.toLowerCase().includes(p))) {
    score = 0;
    feedback.push('Слишком простой пароль');
  }
  
  return { valid: score >= 3, score, feedback };
}

// ═══════════════════════════════════════════════════════════════════════
// Сохранённые функции (из Pack 1)
// ═══════════════════════════════════════════════════════════════════════

export async function isRoomHost(prisma, roomId: string, userId: string): Promise<boolean> {
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    select: { hostID: true }
  });
  return room?.hostID === userId;
}

export function requireHost(prisma) {
  return async (request: any, reply: any) => {
    const { id: roomId } = request.params;
    const userId = request.user.id;
    const room = await prisma.room.findUnique({
      where: { id: roomId },
      select: { hostID: true }
    });
    if (!room) return reply.status(404).send({ error: 'Room not found' });
    if (room.hostID !== userId) {
      return reply.status(403).send({ error: 'Only host can control playback' });
    }
  };
}

export async function sanitizeChatMessage(clientMsg: any, user: { id: string; username: string; role: string }) {
  return {
    type: 'chat',
    roomID: clientMsg.roomID,
    id: clientMsg.id || crypto.randomUUID(),
    senderID: user.id,
    senderName: user.username,
    senderRole: user.role,
    text: sanitizeText(clientMsg.text),
    timestamp: Date.now(),
  };
}

function sanitizeText(text: string): string {
  if (!text || typeof text !== 'string') return '';
  let cleaned = text
    .replace(/<[^>]*>/g, '')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&').replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'").replace(/&#x2F;/g, '/');
  if (cleaned.length > 150) cleaned = cleaned.substring(0, 150);
  cleaned = cleaned.replace(/[\x00-\x1F\x7F]/g, '');
  return cleaned.trim();
}

export async function hashRoomPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, 10);
}

export async function verifyRoomPassword(plain: string, hashed: string): Promise<boolean> {
  try { return await bcrypt.compare(plain, hashed); } catch { return false; }
}

const rlMap = new Map<string, { count: number; resetAt: number }>();

export function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const e = rlMap.get(userId);
  if (!e || now > e.resetAt) {
    rlMap.set(userId, { count: 1, resetAt: now + 1000 });
    return true;
  }
  if (e.count >= 10) return false;
  e.count++;
  return true;
}

setInterval(() => {
  const now = Date.now();
  for (const [k, v] of rlMap) if (now > v.resetAt) rlMap.delete(k);
}, 60_000);
