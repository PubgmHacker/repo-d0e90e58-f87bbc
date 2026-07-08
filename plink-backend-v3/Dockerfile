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
RUN npx prisma generate
EXPOSE 8080
CMD ["npx", "tsx", "src/index.ts"]
