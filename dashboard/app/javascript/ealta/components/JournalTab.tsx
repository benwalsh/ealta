import { useState } from 'react'
import { useJournal } from '../api'
import { useLang } from '../lang'
import { CalendarPicker } from './CalendarPicker'
import { SourceCitations } from './SourceCitations'
import { NotableBlock } from './NotableBlock'
import { Sparkline } from './Sparkline'

// The Journal: the warm, past-tense story of a completed midnight-to-midnight day. A calendar
// walks back through days (default yesterday, the last finished one); each entry is the day's
// final figures, its narrated facts & folklore, and that day's new & notable. The narration is
// frozen server-side (JournalEntry) — this view just renders it. Reuses the .today-card idiom.
export function JournalTab({ onSelect }: { onSelect: (sci: string) => void }) {
  const [date, setDate] = useState<string | null>(null) // null → yesterday (the default)
  const { data, isLoading, isError } = useJournal(date)
  const { t, lang } = useLang()

  if (isLoading || !data) {
    return <p className="dir-loading">{isError ? '—' : '…'}</p>
  }

  const pick = (b: { en: string; ga: string }) => (lang === 'ga' ? b.ga : b.en)
  const bullets = lang === 'ga' ? data.summary.ga : data.summary.en
  const f = data.figures
  const busiest = f.busiest

  return (
    <section className="journal">
      <CalendarPicker date={data.date} available={data.available} onChange={setDate} />

      {data.date ? (
        <>
          <article className="today-card">
            <header className="today-head">
              <span className="today-word">{t('Journal', 'Dialann')}</span>
              <span className="today-date">{pick(data.date_label)}</span>
            </header>
            <hr className="today-rule" />

            {data.day_lore && (
              <p className="journal-daylore">
                <span className="journal-daylore-title">{pick(data.day_lore.title)}</span>
                <span className="journal-daylore-gloss"> — {pick(data.day_lore.gloss)}</span>
              </p>
            )}

            <ul className="journal-figures">
              <li>
                <b>{f.species.toLocaleString()}</b> {t('species', 'speiceas')}
              </li>
              <li>
                <b>{f.detections.toLocaleString()}</b> {t('detections', 'aimsithe')}
              </li>
              {busiest && (
                <li>
                  {t('busiest', 'ba ghnóthaí')}{' '}
                  <button type="button" className="journal-fig-bird" onClick={() => onSelect(busiest.sci)}>
                    {lang === 'ga' && busiest.ga ? busiest.ga : busiest.en}
                  </button>{' '}
                  <b>{busiest.count.toLocaleString()}</b>
                </li>
              )}
            </ul>

            {/* The day's shape — a stilled, greyscale curve (this day is finished, not live). */}
            {data.sparkline?.path && (
              <div className="journal-spark">
                <Sparkline paths={data.sparkline} muted />
                <div className="journal-spark-axis">
                  <span>00:00</span>
                  <span>06:00</span>
                  <span>12:00</span>
                  <span>18:00</span>
                  <span>24:00</span>
                </div>
              </div>
            )}

            {bullets.length && data.source !== 'template' ? (
              // A bird name in the prose carries data-sci — delegate clicks to open its card.
              <ul
                className="today-summary"
                onClick={(e) => {
                  const el = (e.target as HTMLElement).closest<HTMLElement>('[data-sci]')
                  if (el?.dataset.sci) onSelect(el.dataset.sci)
                }}
              >
                {bullets.map((html, i) => (
                  <li key={i} dangerouslySetInnerHTML={{ __html: html }} />
                ))}
              </ul>
            ) : (
              <p className="ed-empty">{t('A quiet day at the station.', 'Lá ciúin ag an stáisiún.')}</p>
            )}

            <SourceCitations sources={data.sources} />

            {data.quotes?.map((q) => (
              <figure key={`${q.sci}-${q.kind}`} className={`journal-lore is-${q.kind}`}>
                <blockquote className="journal-lore-text">
                  {lang === 'ga' && q.text_ga ? q.text_ga : q.text}
                </blockquote>
                <figcaption className="journal-lore-credit">
                  {q.attribution}
                  {q.attribution ? ' · ' : ''}
                  <button type="button" className="journal-lore-bird" onClick={() => onSelect(q.sci)}>
                    {lang === 'ga' && q.ga ? q.ga : q.en}
                  </button>
                </figcaption>
              </figure>
            ))}
          </article>

          <NotableBlock groups={data.notable} onSelect={onSelect} />
        </>
      ) : (
        <p className="ed-empty">
          {t('No completed days yet — come back tomorrow.', 'Gan lá iomlán fós — fill amárach.')}
        </p>
      )}
    </section>
  )
}
