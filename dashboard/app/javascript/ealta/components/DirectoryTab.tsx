import { useMemo, useState } from 'react'
import { useDirectory } from '../api'
import { useLang } from '../lang'
import { elapsed } from '../time'
import { FollowButton } from './FollowButton'
import type { Sort, Scope, Conservation } from '../types'

// The species directory (Eolaí) — the illustrated guide. Each plate echoes the detail
// card: a follow mark, the conservation status above the name, the binomial, and the
// all-time / today / first-heard figures.
// BoCCI list → its display name + a tooltip gloss (the BirdWatch Ireland wording). The
// display reads "Red/Amber/Green list" (the list's proper name), not a bare colour.
const CONS: Record<'red' | 'amber' | 'green', { name: string; note: string }> = {
  red: { name: 'Red list', note: 'BoCCI Red list — high conservation concern in Ireland' },
  amber: { name: 'Amber list', note: 'BoCCI Amber list — moderate conservation concern in Ireland' },
  green: { name: 'Green list', note: 'BoCCI Green list — least conservation concern in Ireland' },
}
const consOf = (c: Conservation) => (c ? CONS[c] : null)

const SORTS: { id: Sort; en: string; ga: string }[] = [
  { id: 'count', en: 'most heard', ga: 'is mó' },
  { id: 'recent', en: 'most recent', ga: 'is déanaí' },
  { id: 'alpha', en: 'a → z', ga: 'a → z' },
]
const SCOPES: { id: Scope; en: string; ga: string }[] = [
  { id: 'heard', en: 'heard', ga: 'cloiste' },
  { id: 'all', en: 'all species', ga: 'gach speiceas' },
]

// Fold away fadas/case so "cag" finds "Cág" and "eabha" finds "Éabha" — a forgiving
// substring match, not a full search engine.
const fold = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

export function DirectoryTab({ onSelect }: { onSelect: (sci: string) => void }) {
  const [sort, setSort] = useState<Sort>('count')
  const [scope, setScope] = useState<Scope>('heard')
  const [query, setQuery] = useState('')
  const { data, isLoading } = useDirectory(sort, scope)
  const { lang, t } = useLang()

  const primary = (en: string, ga: string | null) => (lang === 'ga' && ga ? ga : en)
  const gloss = (en: string, ga: string | null) => (lang === 'ga' ? en : ga)

  // Alpha sort follows the primary (displayed) language, so a→z matches the name the
  // reader sees — English names in English, Irish (with fadas collated correctly) in
  // Irish. Done here rather than server-side so it re-sorts live on the language toggle
  // without another round-trip (and without splitting the cache by language).
  const sorted = useMemo(() => {
    if (!data) return []
    if (sort !== 'alpha') return data.species
    const collator = new Intl.Collator(lang === 'ga' ? 'ga' : 'en', { sensitivity: 'base' })
    return [...data.species].sort((a, b) => collator.compare(primary(a.en, a.ga), primary(b.en, b.ga)))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, sort, lang])

  // Narrow by name as you type — a quiet filter over the already-fetched list (EN, GA,
  // and the binomial), fada- and case-insensitive. No endpoint, no round-trip.
  const species = useMemo(() => {
    const q = fold(query.trim())
    if (!q) return sorted
    return sorted.filter(
      (e) => fold(e.en).includes(q) || (e.ga && fold(e.ga).includes(q)) || fold(e.sci).includes(q),
    )
  }, [sorted, query])

  return (
    <section className="dir">
      <div className="dir-controls">
        <div className="dir-group" role="tablist" aria-label="which birds">
          {SCOPES.map((s) => (
            <button
              key={s.id}
              className={`dir-opt${scope === s.id ? ' is-on' : ''}`}
              aria-current={scope === s.id ? 'true' : undefined}
              onClick={() => setScope(s.id)}
            >
              {lang === 'ga' ? s.ga : s.en}
            </button>
          ))}
        </div>
        <div className="dir-group" role="tablist" aria-label="sort">
          {SORTS.map((s) => (
            <button
              key={s.id}
              className={`dir-opt${sort === s.id ? ' is-on' : ''}`}
              aria-current={sort === s.id ? 'true' : undefined}
              onClick={() => setSort(s.id)}
            >
              {lang === 'ga' ? s.ga : s.en}
            </button>
          ))}
        </div>
        <input
          className="dir-filter"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === 'Escape' && setQuery('')}
          placeholder={t('filter by name', 'scag de réir ainm')}
          aria-label={t('Filter by name', 'Scag de réir ainm')}
        />
      </div>

      {isLoading || !data ? (
        <p className="dir-loading">…</p>
      ) : species.length === 0 ? (
        <p className="dir-loading">{t('No birds match', 'Níl aon éan ann')}</p>
      ) : (
        <div className="dir-grid">
          {species.map((e) => {
            const seen = e.count > 0
            const c = consOf(e.conservation)
            return (
              <div key={e.sci} className="dir-cell">
                <FollowButton sci={e.sci} variant="card" />
                <button className={`dir-item${seen ? '' : ' unseen'}`} onClick={() => onSelect(e.sci)}>
                  <span className="dir-plate">
                    {e.image && <img src={e.image} alt={e.en} loading="lazy" />}
                  </span>
                  {c && (
                    <span className="dir-pill" title={c.note}>
                      <span className={`dir-dot ${e.conservation}`} />
                      {c.name}
                    </span>
                  )}
                  <span className="dir-name">
                    {primary(e.en, e.ga)}
                    {gloss(e.en, e.ga) && <span className="dir-gloss"> ({gloss(e.en, e.ga)})</span>}
                  </span>
                  <span className="dir-sci">{e.sci}</span>
                  {seen ? (
                    <span className="dir-stats">
                      <span className="dir-stat">
                        <b>{e.count.toLocaleString()}</b> {t('all', 'riamh')}
                      </span>
                      <span className="dir-stat">
                        <b>{e.today.toLocaleString()}</b> {t('today', 'inniu')}
                      </span>
                      {e.first_seen && (
                        <span className="dir-stat">
                          <b>{elapsed(e.first_seen, lang)}</b> {t('first', 'céad')}
                        </span>
                      )}
                    </span>
                  ) : (
                    <span className="dir-stats dir-unseen-note">
                      {t('not yet heard', 'gan chloisteáil fós')}
                    </span>
                  )}
                </button>
              </div>
            )
          })}
        </div>
      )}
    </section>
  )
}
