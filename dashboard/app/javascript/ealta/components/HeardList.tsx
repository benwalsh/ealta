import { useLang } from '../lang'
import type { Tally } from '../types'

// The roll of birds: bilingual name, freshest first, one line of meta each. Shared by Live's
// "Recently heard" (meta = time-ago, a moving window) and the Journal's "Heard this day" (meta =
// the clock time it was last heard, a finished day). One component so the two tenses of the same
// section can never drift apart — the caller supplies only the heading and how to say *when*.
export function HeardList({
  title,
  heard,
  meta,
  onSelect,
}: {
  title: string
  heard: Tally[]
  meta: (t: Tally) => string
  onSelect: (sci: string) => void
}) {
  const { lang } = useLang()
  const primary = (en: string, ga: string | null) => (lang === 'ga' && ga ? ga : en)
  const gloss = (en: string, ga: string | null) => (lang === 'ga' ? (ga ? en : null) : ga)

  if (!heard.length) return null

  return (
    <section className="recent">
      <h2 className="section-tag">{title}</h2>
      <ul className="ed-list">
        {heard.map((r) => (
          <li key={r.sci}>
            <button className="ed-row" onClick={() => onSelect(r.sci)}>
              <span className="ed-row-name">
                {primary(r.en, r.ga)}
                {gloss(r.en, r.ga) && <em className="ed-gloss">{gloss(r.en, r.ga)}</em>}
              </span>
              <span className="ed-row-meta">{meta(r)}</span>
            </button>
          </li>
        ))}
      </ul>
    </section>
  )
}
