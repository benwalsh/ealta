import { useStats } from '../api'
import { useLang } from '../lang'
import { shortDate } from '../time'
import { WindowPicker } from './WindowPicker'

// The stats page: the lifetime record, in the same broadsheet idiom as the home
// page. No cards, no tiles, no rounded corners — ruled hairlines and right angles.
// Serif (EB Garamond) for names; monospace (IBM Plex Mono) for every count, date
// and label. The page renders; it never computes (all numbers come from /api/stats).
const PERIOD_GA: Record<string, string> = {
  'Past hour': 'An uair seo caite',
  'Past 24 hours': 'Le 24 uair',
  'Past 7 days': 'Le 7 lá',
  'All time': 'Gach am',
}

export function StatsTab({
  onSelect,
  windowHours,
  onWindow,
  windows,
}: {
  onSelect: (sci: string) => void
  windowHours: number
  onWindow: (hours: number) => void
  windows: [string, number][]
}) {
  const { data, isLoading } = useStats(windowHours)
  const { lang, t } = useLang()

  if (isLoading || !data) {
    return <p style={{ textAlign: 'center', padding: '60px', color: 'var(--ink-soft)' }}>…</p>
  }

  const primary = (en: string, ga: string | null) => (lang === 'ga' && ga ? ga : en)
  const gloss = (en: string, ga: string | null) => (lang === 'ga' ? (ga ? en : null) : ga)
  const period = (label: string) => (lang === 'ga' ? (PERIOD_GA[label] ?? label) : label)
  const c = data.summary_cards
  const max = Math.max(data.top_species[0]?.count ?? 1, 1)

  const name = (en: string, ga: string | null) => (
    <span className="st-name">
      {primary(en, ga)}
      {gloss(en, ga) && <em className="st-gloss">{gloss(en, ga)}</em>}
    </span>
  )

  return (
    <section className="st">
      {/* 1. Continuity band — the lifetime numbers, as a masthead dateline. */}
      <div className="st-cont">
        <div className="st-cont-item">
          <span className="st-fig">{c.species_logged.toLocaleString()}</span>
          <span className="st-lbl">{t('Species logged', 'Speicis logáilte')}</span>
        </div>
        <div className="st-cont-item">
          <span className="st-fig">{c.detections_all_time.toLocaleString()}</span>
          <span className="st-lbl">{t('Detections all-time', 'Aimsithe san iomlán')}</span>
        </div>
        <div className="st-cont-item">
          <span className="st-fig">{c.days_listening.toLocaleString()}</span>
          <span className="st-lbl">{t('Days listening', 'Laethanta ag éisteacht')}</span>
        </div>
      </div>

      {/* 2. Most heard — ranked, with a thin inline measure (never a heavy bar). The
          window picker rides in the header and rescopes the ranking. */}
      <div className="st-block">
        <div className="st-head-row">
          <h2 className="st-head">{t('Most heard', 'Is mó a cloiseadh')}</h2>
          <WindowPicker windows={windows} value={windowHours} onChange={onWindow} />
        </div>
        {data.top_species.length > 0 ? (
          <ol className="st-ranked">
            {data.top_species.map((s) => (
              <li key={s.sci}>
                <button className="st-row" onClick={() => onSelect(s.sci)}>
                  {name(s.en, s.ga)}
                  <span className="st-measure">
                    <i style={{ width: `${(s.count / max) * 100}%` }} />
                  </span>
                  <span className="st-count">{s.count.toLocaleString()}</span>
                </button>
              </li>
            ))}
          </ol>
        ) : (
          <p className="st-empty">{t('Nothing heard in this window.', 'Faic cloiste sa tréimhse seo.')}</p>
        )}
      </div>

      {/* 3. By period + Life list — two ruled columns (stack when narrow). */}
      <div className="st-cols">
        <div className="st-block">
          <h2 className="st-head">{t('By period', 'De réir tréimhse')}</h2>
          <ul className="st-rows">
            {data.by_period.map((p) => (
              <li key={p.label} className="st-rrow">
                <span className="st-rlabel">{period(p.label)}</span>
                <span className="st-rfig">{p.count.toLocaleString()}</span>
              </li>
            ))}
          </ul>
        </div>
        {data.first_seen.length > 0 && (
          <div className="st-block st-col-right">
            <h2 className="st-head">{t('Life list', 'Liosta saoil')}</h2>
            <ul className="st-rows">
              {data.first_seen.map((e) => (
                <li key={e.sci}>
                  <button className="st-rrow st-rbtn" onClick={() => onSelect(e.sci)}>
                    {name(e.en, e.ga)}
                    <span className="st-rdate">{shortDate(e.first_seen, lang)}</span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </section>
  )
}
