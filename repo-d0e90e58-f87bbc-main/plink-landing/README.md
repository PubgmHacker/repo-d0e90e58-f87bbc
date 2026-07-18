# Plink Landing Site

Marketing site (rave.io-style) for Plink downloads.

## Dev

```bash
npm install
npm run dev
# → http://localhost:3000
```

## Build

```bash
npm run build
npm start
```

## Deploy (Vercel)

```bash
npx vercel --prod
```

Or connect `plink-landing` folder to Vercel GitHub integration.

## Pages

- `/` — Home (hero, download, features, comparison, pricing, testimonials)
- `/download` — Platform installers
- `/features`, `/plink-plus`, `/privacy`, `/terms`

## i18n

RU/EN toggle in header (localStorage `plink-locale`).

## Downloads

Place artifacts in `public/downloads/` — see `public/downloads/README.md`.