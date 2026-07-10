import { useLang } from '../lang'
import type { Today } from '../types'

// The almanac — the ambient weather / moon / sun / tide readings — as its own row under
// the sparkline. Leads with the station's live status (a pulsing green dot when the mic
// loop is alive, a dead red one when it's stalled), then muted mono line-icon + label
// pairs; never emoji. Pre-shaped in Ruby; this just iterates and prints.
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
          <i className={`ti ${f.icon}`} aria-hidden="true" /> {pick(f)}
        </li>
      ))}
    </ul>
  )
}
