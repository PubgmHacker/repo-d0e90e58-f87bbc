FROM node:20-slim

# OpenSSL + yt-dlp + ffmpeg для Pack 3 (stream extraction)
RUN apt-get update -y && apt-get install -y \
    openssl \
    yt-dlp \
    ffmpeg \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY . .
RUN chmod +x start.sh
RUN npx prisma generate
EXPOSE 8080
# 🔧 FIX 500-on-signin: run prisma db push at container start so DB schema
# stays in sync with schema.prisma. Without this, adding new fields (e.g.
# displayName, coverURL) breaks every default-select query because the
# Prisma client knows about columns the database doesn't have.
# start.sh prints step-by-step banners + redirects stdin from /dev/null so
# prisma can NEVER hang waiting for interactive confirmation.
CMD ["./start.sh"]
