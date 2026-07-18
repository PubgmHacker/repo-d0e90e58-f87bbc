/** Central download / store links — update APP_STORE_ID when live on App Store Connect */
export const APP_STORE_ID = process.env.NEXT_PUBLIC_APP_STORE_ID ?? '6750000001';

export const LINKS = {
  appStore: `https://apps.apple.com/app/plink-watch-together/id${APP_STORE_ID}`,
  playStore: 'https://play.google.com/store/apps/details?id=com.plink.app',
  mac: '/downloads/Plink.dmg',
  windows: '/downloads/Plink-1.0.0-x64-setup.exe',
  androidApk: '/downloads/app-debug.apk',
} as const;