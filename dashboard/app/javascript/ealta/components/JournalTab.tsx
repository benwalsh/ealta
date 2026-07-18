import { useState } from 'react'
import { useJournal } from '../api'
import { useLang } from '../lang'
import { CalendarPicker } from './CalendarPicker'
import { SourceCitations } from './SourceCitations'
import { LoreCredit } from './LoreCredit'
import { NotableBlock } from './NotableBlock'
import { Sparkline } from './Sparkline'

// A zero-detection day's honest one-liner. We can't tell a genuinely quiet day from a dead mic, so
// rather than assert silence we say how long the mic actually listened (coverage_hours): "offline for
// much of the day — recorded N of 24 hours" vs "listened N of 24 and logged nothing". When coverage
// is unknown (an old day past heartbeat retention), fall back to the plain lines.
function quietLine(
  data: { offline: boolean; mic_hours: number | null },
  t: (en: string, ga: string) => string,
) {
  const h = data.mic_hours
  if (data.offline) {
    return h == null
      ? t('The station was offline this day.', 'Bhí an stáisiún as líne an lá seo.')
      : t(
          `The station was offline for much of this day — the mic recorded ${h} of 24 hours.`,
          `Bhí an stáisiún as líne ar feadh cuid mhór den lá seo — níor thaifead an micreafón ach ${h}/24 uair.`,
        )
  }
  return h == null
    ? t('A quiet day at the station.', 'Lá ciúin ag an stáisiún.')
    : t(
        `A quiet day — the mic listened ${h} of 24 hours and logged nothing.`,
        `Lá ciúin — bhí an micreafón ag éisteacht ${h}/24 uair agus níor thaifead sé faic.`,
      )
}

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
  // Irish when the station is bilingual and the field has it, else English (which is always set).
  const say = (en: string | null, ga: string | null) => (lang === 'ga' && ga ? ga : en)
  const bullets = lang === 'ga' ? data.summary.ga : data.summary.en
  const f = data.figures
  const busiest = f.busiest
  const hero = data.hero

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
              <div className="journal-daylore">
                <p className="journal-daylore-line">
                  <span className="journal-daylore-title">{pick(data.day_lore.title)}</span>
                  <span className="journal-daylore-gloss"> — {pick(data.day_lore.gloss)}</span>
                </p>
                {data.day_lore.lore && (
                  <p className="journal-daylore-lore">{say(data.day_lore.lore.en, data.day_lore.lore.ga)}</p>
                )}
                {data.day_lore.sources.length > 0 && (
                  <p className="journal-daylore-credit">
                    {data.day_lore.sources.map((s) => s.host).join(' · ')}
                  </p>
                )}
              </div>
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

            {/* The keeper's own line for the day, set apart above the narration — the letter
                carries the same words, so the two never diverge. Rare. */}
            {data.note && (
              <aside className="journal-note">
                <p className="journal-note-label">{t('A note from the station', 'Nóta ón stáisiún')}</p>
                <p className="journal-note-body">{data.note}</p>
              </aside>
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
              <p className="ed-empty">{quietLine(data, t)}</p>
            )}

            {/* A short deep dive on the day's hero — its sourced summary. The bundle's fact
                blocks are NOT listed here: they are the raw material the day's narration above
                is written from, and repeating them as bullets underneath said the same things
                twice, in a flatter voice. The folklore coda below is what follows the summary. */}
            {hero && hero.description && (
              <div className="journal-hero">
                <button type="button" className="journal-hero-name" onClick={() => onSelect(hero.sci)}>
                  {say(hero.en, hero.ga)}
                </button>
                <p className="journal-hero-desc">{say(hero.description, hero.description_ga)}</p>
              </div>
            )}

            <SourceCitations sources={data.sources} />

            {data.quotes?.map((q) => (
              <figure key={`${q.sci}-${q.kind}`} className={`journal-lore is-${q.kind}`}>
                <blockquote className="journal-lore-text">
                  {lang === 'ga' && q.text_ga ? q.text_ga : q.text}
                </blockquote>
                <figcaption className="journal-lore-credit">
                  {q.source ? <LoreCredit source={q.source} /> : q.attribution}
                  {q.source || q.attribution ? ' · ' : ''}
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
