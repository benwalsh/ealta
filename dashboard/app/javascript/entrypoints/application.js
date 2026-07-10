// The server-rendered bundle: Turbo + the Stimulus controllers. Loaded by the
// application layout (so /kiosk and /station keep their refresh/cycle behaviour).
// The React SPA on `/` has its own entrypoint (app.tsx).
import '@hotwired/turbo-rails'
import '../controllers'
// The station/kiosk footers render the same Tabler line-icons the SPA almanac uses.
import '@tabler/icons-webfont/dist/tabler-icons.min.css'
