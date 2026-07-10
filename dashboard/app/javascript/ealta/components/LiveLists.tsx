import { useLang } from '../lang'
import { ago } from '../time'
import type { Tally } from '../types'

// Live's reading body: Recently heard — the window's birds, freshest first, with
// time-ago. The present-tense counterpart to the collage (which is *which* birds; this
// is *when*). Rankings, life list and first-seen deliberately live on Stats, not here.
export function LiveLists({ recent, onSelect }: { recent: Tally[]; onSelect: (sci: string) => void }) {
  const { t, lang } = useLang()
  const primary = (en: string, ga: string | null) => (lang === 'ga' && ga ? ga : en)
  const gloss = (en: string, ga: string | null) => (lang === 'ga' ? (ga ? en : null) : ga)

  if (!recent.length) return null

  return (
    <section className="recent">
      <h2 className="section-tag">{t('Recently heard', 'Cloiste le déanaí')}</h2>
      <ul className="ed-list">
        {recent.map((r) => (
          <li key={r.sci}>
            <button className="ed-row" onClick={() => onSelect(r.sci)}>
              <span className="ed-row-name">
                {primary(r.en, r.ga)}
                {gloss(r.en, r.ga) && <em className="ed-gloss">{gloss(r.en, r.ga)}</em>}
              </span>
              <span className="ed-row-meta">{ago(r.last_time, lang)}</span>
            </button>
          </li>
        ))}
      </ul>
    </section>
  )
}
