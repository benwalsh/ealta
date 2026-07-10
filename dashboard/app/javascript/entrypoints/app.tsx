// The React SPA entrypoint for `/`. Mounts into #ealta-app, which carries a
// data-bootstrap JSON blob (current_user, ui_lang, windows) so the first paint
// needs no round-trip. Chrome + tabs get built out in later phases.
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
// The publication's typefaces, self-hosted (bundled by Vite, no CDN): EB Garamond
// (the Sabon-role serif — names, mastheads, prose) and IBM Plex Mono (the measure —
// every number and small label). Tabler line icons for the ambient footer glyphs.
import '@fontsource/eb-garamond/400.css'
import '@fontsource/eb-garamond/500.css'
import '@fontsource/eb-garamond/400-italic.css'
import '@fontsource/ibm-plex-mono/400.css'
import '@fontsource/ibm-plex-mono/500.css'
import '@tabler/icons-webfont/dist/tabler-icons.min.css'
import { App } from '../ealta/App'

const el = document.getElementById('ealta-app')
if (el) {
  const bootstrap = JSON.parse(el.dataset.bootstrap || '{}')
  createRoot(el).render(
    <StrictMode>
      <App bootstrap={bootstrap} />
    </StrictMode>,
  )
}
