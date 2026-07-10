import { useLang } from '../lang'
import type { NotableGroups, NotableItem, NotableKind } from '../types'

// The category headings, bilingual — the day's news, framed as an almanac would frame it.
// 'favourites' is a fourth, personal category added client-side (the signed-in reader's
// followed birds heard today), never server news.
type Category = NotableKind | 'favourites'
const HEADING: Record<Category, { en: string; ga: string }> = {
  rarity: { en: 'Rare visitors', ga: 'Cuairteoirí annamha' },
  seasonal: { en: 'Returning migrants', ga: 'Imircigh ag filleadh' },
  first_ever: { en: 'First recordings', ga: 'Céadtaifid' },
  favourites: { en: 'Your favourites', ga: 'Do rogha éin' },
}
// The order the lines read in — news first, the personal line last.
const ORDER: Category[] = ['rarity', 'seasonal', 'first_ever', 'favourites']

// New & notable: info-only category lines (no folklore, no prose — that lives in the
// Journal). Each bird is a button to its card. Renders nothing when there's no news and
// no followed birds were heard — no empty banner on a quiet day. (The live/offline status
// is on the almanac strip, not here.)
export function NotableBlock({
  groups,
  favourites = [],
  onSelect,
}: {
  groups: NotableGroups
  favourites?: NotableItem[]
  onSelect: (sci: string) => void
}) {
  const { t, lang } = useLang()
  const lists: Record<Category, NotableItem[]> = { ...groups, favourites }
  const rows = ORDER.filter((c) => lists[c]?.length)
  if (!rows.length) return null

  const name = (it: NotableItem) => (lang === 'ga' && it.ga ? it.ga : it.en)

  return (
    <section className="notable" aria-label={t('New and notable', 'Nua is suntasach')}>
      <h2 className="section-tag">{t('New & notable', 'Nua is suntasach')}</h2>
      <ul className="notable-list">
        {rows.map((cat) => (
          <li key={cat} className="notable-row">
            <span className="notable-kind">{t(HEADING[cat].en, HEADING[cat].ga)}</span>
            <span className="notable-names">
              {lists[cat].map((it, i) => (
                <button key={it.sci} type="button" className="notable-name" onClick={() => onSelect(it.sci)}>
                  {name(it)}
                  {i < lists[cat].length - 1 ? <span className="notable-sep">,</span> : null}
                </button>
              ))}
            </span>
          </li>
        ))}
      </ul>
    </section>
  )
}
