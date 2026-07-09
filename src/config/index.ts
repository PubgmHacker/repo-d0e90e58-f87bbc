// src/config/index.ts — Pack 1.1: увеличенные TTL
function required(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`Missing env: ${key}`);
  return val;
}

export const config = {
  DATABASE_URL: process.env.DATABASE_URL || required('DATABASE_URL'),
  JWT_SECRET: process.env.JWT_SECRET || 'dev-secret-change-me',
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || 'dev-refresh-secret-change-me',
  CORS_ORIGIN: process.env.CORS_ORIGIN || '*',
  PORT: parseInt(process.env.PORT || '8080'),
  
  REDIS_URL: process.env.REDIS_URL || '',
  SENTRY_DSN: process.env.SENTRY_DSN || '',
  SLACK_WEBHOOK_URL: process.env.SLACK_WEBHOOK_URL || '',
  
  // 🔧 Pack 1.1: Увеличенные TTL для удобства пользователей
  // Access token = 7 дней (не выкидывает из 6-часового фильма)
  // Refresh token = 90 дней (редко просит пароль)
  ACCESS_TOKEN_TTL: process.env.ACCESS_TOKEN_TTL || '7d',
  REFRESH_TOKEN_TTL_DAYS: parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '90'),
  
  NODE_ENV: process.env.NODE_ENV || 'development',
  isProduction: process.env.NODE_ENV === 'production',
};
