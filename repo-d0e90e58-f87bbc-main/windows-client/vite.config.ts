import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': {
        target: 'https://plink-backend-production-ef31.up.railway.app',
        changeOrigin: true,
        secure: true,
      },
    },
  },
  envPrefix: ['VITE_', 'TAURI_'],
})
