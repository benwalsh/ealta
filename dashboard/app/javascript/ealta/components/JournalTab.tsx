import { useState } from 'react'
import { useJournal } from '../api'
import { useLang } from '../lang'
import { clock } from '../time'
import { CalendarPicker } from './CalendarPicker'
import { HeardList } from './HeardList'
import { DetectionStats } from './DetectionStats'
import { LoreCredit } from './LoreCredit'
import { NotableBlock } from './NotableBlock'
import { Sparkline } from './Sparkline'

// A zero-detection day's honest one-liner. We can't tell a genuinely quiet day from a dead mic, so
// rather than assert silence we say how long the mic actually listened (mic_hours): "offline for
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

// The Journal: the warm, past-tense story of a completed midnight-to-midnight day. A calendar walks
// back through days (default yesterday, the last finished one). The day leads with its date and any
// féilire/daylore, then the narrated story and its closing folklore; the figures follow at the
// bottom as a quiet table — the story speaks first, the numbers just sit under it. The narration is
// frozen server-side (JournalEntry); this view only renders it.
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

  return (
    <section className="journal">
      <CalendarPicker
        date={data.date}
        dateLabel={pick(data.date_label)}
        available={data.available}
        onChange={setDate}
      />

      {data.date ? (
        <>
          <article className="today-card">
            {/* No dateline, headline or dividing rules — the picker above IS the date, and each
                part of the entry is set off by its mono tag alone. The day's féilire character
                leads: the feast or season under its own tag, then its gloss and any curated
                day-lore (a dúchas story or a curated passage). */}
            {data.day_lore && (
              <section className="journal-section journal-day">
                <h2 className="section-tag">{pick(data.day_lore.title)}</h2>
                <p className="journal-day-gloss">{pick(data.day_lore.gloss)}</p>
                {/* A station's own curated deep-dive on the day's tradition (rare; bilingual). */}
                {data.day_lore.lore && (
                  <p className="journal-day-lore">{say(data.day_lore.lore.en, data.day_lore.lore.ga)}</p>
                )}
                {/* The day's lore, richest-first: a curated custom/belief/legend (day_lore) if the
                    day has one, else the felire_lore FLOOR (the Óengus saint — its legible gloss,
                    or its promoted verse — then the Old Irish once verified). Both close on a
                    reader-context note and a source credit. */}
                {data.day_lore.day ? (
                  <>
                    {data.day_lore.day.title && (
                      <p className="journal-day-title">{data.day_lore.day.title}</p>
                    )}
                    {data.day_lore.day.text && <p className="journal-day-lore">{data.day_lore.day.text}</p>}
                    {data.day_lore.day.quote && (
                      <p className="journal-day-verse">{data.day_lore.day.quote}</p>
                    )}
                    {data.day_lore.day.note && <p className="journal-day-note">{data.day_lore.day.note}</p>}
                    {data.day_lore.day.credit && (
                      <p className="journal-day-credit">{data.day_lore.day.credit}</p>
                    )}
                  </>
                ) : data.day_lore.narrative ? (
                  (() => {
                    const n = data.day_lore!.narrative!
                    return (
                      <>
                        <p className={n.verse ? 'journal-day-verse' : 'journal-day-lore'}>{n.text}</p>
                        {n.quatrain_ga && <p className="journal-day-verse-ga">{n.quatrain_ga}</p>}
                        {n.note && <p className="journal-day-note">{n.note}</p>}
                        {n.credit && <p className="journal-day-credit">{n.credit}</p>}
                      </>
                    )
                  })()
                ) : null}
                {data.day_lore.sources.length > 0 && (
                  <p className="journal-day-credit">{data.day_lore.sources.map((s) => s.host).join(' · ')}</p>
                )}
              </section>
            )}

            {/* The keeper's own line for the day, set apart above the narration — the letter
                carries the same words, so the two never diverge. Rare. */}
            {data.note && (
              <aside className="journal-note">
                <p className="journal-note-label">{t('A note from the station', 'Nóta ón stáisiún')}</p>
                <p className="journal-note-body">{data.note}</p>
              </aside>
            )}

            <section className="journal-section journal-birds">
              <h2 className="section-tag">{t('Birds', 'Éin')}</h2>
              {bullets.length && data.source !== 'template' ? (
                // A bird name in the prose carries data-sci — delegate clicks to open its card.
                // (The facts & folklore citations sit inline beside each bird, above.)
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
            </section>

            {/* Local colour: a rotating story from the station's own ground — the coast's standing
                character, and what carries the entry on a birdless day. Its heading is the place. */}
            {data.place && (
              <section className="journal-section journal-place">
                <h2 className="section-tag">{data.place.place}</h2>
                {data.place.title && <p className="journal-day-title">{data.place.title}</p>}
                {data.place.text && <p className="journal-day-lore">{data.place.text}</p>}
                {data.place.quote && <p className="journal-day-verse">{data.place.quote}</p>}
                {data.place.note && <p className="journal-day-note">{data.place.note}</p>}
                {(data.place.narrator || data.place.credit) && (
                  <p className="journal-day-credit">
                    {data.place.narrator ? `${t('Told by', 'Arna insint ag')} ${data.place.narrator}` : ''}
                    {data.place.narrator && data.place.credit ? ' · ' : ''}
                    {data.place.credit}
                  </p>
                )}
              </section>
            )}

            {data.quotes?.length ? (
              <section className="journal-section journal-lore-block">
                <h2 className="section-tag">{t('Lore & Wisdom', 'Béaloideas is eagna')}</h2>
                {data.quotes.map((q) => {
                  const body = lang === 'ga' && q.text_ga ? q.text_ga : q.text
                  return (
                    <figure key={`${q.sci}-${q.kind}`} className={`journal-lore is-${q.kind}`}>
                      {q.title && <p className="journal-lore-title">{q.title}</p>}
                      {body && <blockquote className="journal-lore-text">{body}</blockquote>}
                      {q.quote && <blockquote className="journal-lore-verse">{q.quote}</blockquote>}
                      {q.note && <p className="journal-lore-note">{q.note}</p>}
                      <figcaption className="journal-lore-credit">
                        {q.credit ? q.credit : q.source ? <LoreCredit source={q.source} /> : q.attribution}
                        {q.credit || q.source || q.attribution ? ' · ' : ''}
                        <button type="button" className="journal-lore-bird" onClick={() => onSelect(q.sci)}>
                          {lang === 'ga' && q.ga ? q.ga : q.en}
                        </button>
                      </figcaption>
                    </figure>
                  )
                })}
              </section>
            ) : null}

            {/* The day in figures — kept to the bottom: the story leads, the numbers just follow.
                The stilled greyscale curve is the day's shape (finished, not live). */}
            <div className="journal-stats">
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
              {busiest && (
                <p className="journal-most-detected">
                  <span className="journal-most-label">{t('Most detected', 'Ba mhinice')}</span>
                  <button type="button" className="journal-fig-bird" onClick={() => onSelect(busiest.sci)}>
                    {lang === 'ga' && busiest.ga ? busiest.ga : busiest.en}
                  </button>{' '}
                  {busiest.count.toLocaleString()}
                </p>
              )}

              {/* Live's Recently heard, locked to this day: the same roll of birds, saying the
                  clock time each was last heard rather than how long ago — on a finished day the
                  elapsed figure measures the distance to now, not anything about the day. The
                  shared stats line heads it, exactly as it heads Recently heard on Live. */}
              <DetectionStats
                detections={f.detections}
                species={f.species}
                durationSeconds={f.duration_seconds}
              />
              <HeardList
                title={t('Heard this day', 'Cloiste an lá seo')}
                heard={data.heard}
                meta={(r) => clock(r.last_time)}
                onSelect={onSelect}
              />
            </div>
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
