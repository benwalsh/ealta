import { useLang } from '../lang'
import type { Today } from '../types'

// The almanac — the ambient weather / moon / sun / tide readings — as its own row under
// the sparkline. Leads with the station's live status (a pulsing green dot when the mic
// loop is alive, a dead red one when it's stalled), then muted mono line-icon + label
// pairs; never emoji. Pre-shaped in Ruby; this just iterates and prints.
// A reading's mark. Everything ambient is a static line-icon; the moon alone is drawn, so
// it shows tonight's actual phase instead of the one crescent `ti-moon` wears all month.
//
// `path` is the SHADOW (MoonPhase#shadow), not the lit part: ink reads as dark, so inking the
// lit region would draw a negative. The disc is always stroked and the shadow filled over it —
// new moon solid, full moon an open circle (nothing dark, so `path` is null), and the lit limb
// always the colour of the page. Same muted weight as the icon font it sits beside.
function MoonGlyph({ path, fallback }: { path?: string | null; fallback: string }) {
  if (path === undefined) return <i className={`ti ${fallback}`} aria-hidden="true" />

  return (
    <svg className="ti alm-moon" viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="1.25" opacity="0.55" />
      {path && <path d={path} fill="currentColor" opacity="0.55" />}
    </svg>
  )
}

export function AlmanacRow({
  today,
  status,
  stickyTop,
}: {
  today: Today
  status: 'listening' | 'offline'
  stickyTop?: number
}) {
  const { t, lang } = useLang()
  if (!today?.footer?.length) return null

  const pick = (item: { en: string; ga: string }) => (lang === 'ga' ? item.ga : item.en)

  return (
    <ul className="today-almanac" style={{ top: stickyTop }}>
      <li className="alm-status">
        <span className={`alm-dot is-${status}`} aria-hidden="true" />
        {status === 'listening' ? t('Listening', 'Ag éisteacht') : t('Offline', 'As líne')}
      </li>
      {today.footer.map((f, i) => (
        <li key={i}>
          <MoonGlyph path={f.svg} fallback={f.icon} /> {pick(f)}
        </li>
      ))}
    </ul>
  )
}
