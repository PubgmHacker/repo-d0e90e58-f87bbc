import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './design/tokens.css'
import './index.css'
import { initPlatformClass } from './lib/platform'
import App from './App.tsx'

initPlatformClass()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
