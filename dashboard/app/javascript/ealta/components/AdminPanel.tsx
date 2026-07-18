import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useHealth } from '../api'
import { ago, stamp } from '../time'
import { SidePanel } from './SidePanel'

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

type Result = { ok: boolean; message: string }

const SECTIONS = [
  { id: 'overview', label: 'Overview' },
  { id: 'station', label: 'Station' },
  { id: 'content', label: 'Content' },
  { id: 'email', label: 'Email' },
  { id: 'broadcast', label: 'Broadcast' },
  { id: 'danger', label: 'Danger zone' },
] as const
type Section = (typeof SECTIONS)[number]['id']

// How the listening state reads at a glance. Freshness keys off the heartbeat, so a genuinely
// quiet night stays "listening" — only a stalled loop goes dark.
const STATUS: Record<string, string> = {
  fresh: 'Listening',
  quiet: 'No signal recently',
  stale: 'Not responding',
  none: 'Nothing heard yet',
}

// The station console. Two kinds of thing only: what an admin can do, and what fails quietly.
// Sectioned rather than one long scroll, with the destructive action alone at the bottom.
export function AdminPanel({ onClose, onBack }: { onClose: () => void; onBack?: () => void }) {
  const qc = useQueryClient()
  const { data: h, isFetching, error } = useHealth(true)
  const [section, setSection] = useState<Section>('overview')
  const [result, setResult] = useState<Result | null>(null)
  const [busy, setBusy] = useState(false)

  const [confirm, setConfirm] = useState('')

  // A broadcast is the most dangerous thing in the console, so the send stays locked until the
  // whole ceremony is done: something written, read back as a preview, a copy landed in your
  // own inbox, and the reader count typed out. The server enforces the count too.
  const [blastSubject, setBlastSubject] = useState('')
  const [blastBody, setBlastBody] = useState('')
  const [blastHtml, setBlastHtml] = useState<string | null>(null)
  const [blastTested, setBlastTested] = useState(false)
  const [blastConfirm, setBlastConfirm] = useState('')

  const yesterday = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10)
  const [journalDate, setJournalDate] = useState(yesterday)
  const [letterDate, setLetterDate] = useState(yesterday)

  // The keeper's note for the NEXT letter. No date to pick: a note is something you say
  // ahead, and the server decides which day that is from the station's own timezone.
  const [note, setNote] = useState('')

  useEffect(() => {
    let live = true
    fetch('/admin/note', { headers: { Accept: 'application/json' } })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((j: { note: string | null }) => {
        if (live) setNote(j.note ?? '')
      })
      .catch(() => {
        if (live) setNote('')
      })
    return () => {
      live = false
    }
  }, [])

  // Drive the empty states off "have I data / am I fetching" rather than react-query's status
  // flags: a failed fetch can settle as paused-pending rather than error, which left the
  // console rendering nothing at all. No state here shows a blank panel.
  const forbidden = String((error as Error | null)?.message ?? '').startsWith('403')

  // Returns the server's result so a caller can react to it (the broadcast unlocks its send
  // only once a test copy has actually gone).
  const mutate = (url: string, method: string, body?: object): Promise<Result | null> => {
    setBusy(true)
    setResult(null)
    return fetch(url, {
      method,
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrf() },
      body: body ? JSON.stringify(body) : undefined,
    })
      .then(async (r) => {
        const j = (await r.json().catch(() => null)) as Result | null
        const outcome = j ?? { ok: r.ok, message: r.ok ? 'Done.' : `Error ${r.status}.` }
        setResult(outcome)
        qc.invalidateQueries({ queryKey: ['health'] })
        return outcome
      })
      .catch(() => {
        setResult({ ok: false, message: 'Request failed.' })
        return null
      })
      .finally(() => setBusy(false))
  }

  // Any edit after a test send invalidates it — otherwise you could test one message and
  // broadcast another.
  const editBlast = (change: () => void) => {
    change()
    setBlastTested(false)
    setBlastHtml(null)
    setBlastConfirm('')
  }

  const l = h?.listening

  // The address mail goes out as. Which box actually runs the sweep is deployment trivia and
  // stays out of the copy — sends_here only decides whether a missing address is a FAULT
  // (it is on the station that mails; it's simply how things are on a laptop or the Pi).
  const delivery = (): { text: string; warn: boolean } => {
    if (!h) return { text: '—', warn: false }
    if (h.alerts.configured) return { text: h.alerts.from ?? '—', warn: false }
    return { text: 'Not configured here', warn: h.letter.sends_here }
  }

  const backup = (): { text: string; warn: boolean } => {
    if (!h) return { text: '—', warn: false }
    if (h.backup.configured) return { text: h.backup.bucket ?? '—', warn: false }
    return h.backup.expected ? { text: 'Not configured', warn: true } : { text: 'Not used here', warn: false }
  }

  return (
    <SidePanel title="Admin" width="wide" onClose={onClose} onBack={onBack} backLabel="Account">
      {result && <p className={`adm-flash ${result.ok ? 'is-ok' : 'is-alert'}`}>{result.message}</p>}

      {!h && isFetching && <p className="adm-lead">Reading the station…</p>}

      {!h && !isFetching && (
        <section className="acct-sec">
          <p className="adm-flash is-alert">
            {forbidden
              ? 'This account does not have admin access on this station.'
              : 'Could not read the station health.'}
          </p>
          {!forbidden && (
            // resetQueries, not refetch: a query that failed can settle into a state where
            // refetch is a no-op, which left the console stuck here until a full page reload.
            <button className="acct-seg" onClick={() => qc.resetQueries({ queryKey: ['health'] })}>
              Try again
            </button>
          )}
        </section>
      )}

      {h && l && (
        <div className="adm-console">
          <nav className="adm-nav" aria-label="Admin sections">
            {SECTIONS.map((s) => (
              <button
                key={s.id}
                className={`adm-nav-item${section === s.id ? ' is-on' : ''}`}
                aria-current={section === s.id ? 'true' : undefined}
                onClick={() => setSection(s.id)}
              >
                {s.label}
              </button>
            ))}
          </nav>

          <div className="adm-pane">
            {section === 'overview' && (
              <>
                <h2 className="acct-h2">Overview</h2>
                <p className="adm-lead">
                  <span className={`adm-dot ${l.freshness}`} />
                  <span>{STATUS[l.freshness] ?? 'Unknown'}</span>
                  {l.last_alive_at && <span className="adm-abs">{stamp(l.last_alive_at)}</span>}
                </p>
                {/* ago() already carries its own "ago" ("3h ago" / "now") — don't add another. */}
                {l.last_heard_at && (
                  <p className="adm-note">
                    Last heard {ago(l.last_heard_at)}
                    {l.last_species ? ` — ${l.last_species.en}` : ''}.
                  </p>
                )}

                <div className="adm-stats">
                  <div className="adm-stat">
                    <span className="adm-fig">{l.detections_today.toLocaleString()}</span>
                    <span className="adm-lbl">Detections today</span>
                  </div>
                  <div className="adm-stat">
                    <span className="adm-fig">{l.species_today}</span>
                    <span className="adm-lbl">Species today</span>
                  </div>
                </div>

                <ul className="acct-rules adm-mt">
                  <li className="acct-rule">
                    <span className="acct-rule-label">Email delivery</span>
                    <span className={delivery().warn ? 'adm-warn' : undefined}>{delivery().text}</span>
                  </li>
                  <li className="acct-rule">
                    <span className="acct-rule-label">Offsite backup</span>
                    <span className={backup().warn ? 'adm-warn' : undefined}>{backup().text}</span>
                  </li>
                  <li className="acct-rule">
                    <span className="acct-rule-label">Alerts waiting to send</span>
                    <span className={h.alerts.events_pending > 0 ? 'adm-warn' : undefined}>
                      {h.alerts.events_pending}
                    </span>
                  </li>
                </ul>

                {l.restartable && (
                  <div className="adm-field adm-mt">
                    <p className="adm-field-label">Microphone listener</p>
                    <p className="adm-field-hint">Restart it if the station has stopped hearing anything.</p>
                    <div className="adm-field-control">
                      <button
                        className="acct-seg"
                        disabled={busy}
                        onClick={() => mutate('/admin/birdnet/restart', 'POST')}
                      >
                        Restart the microphone listener
                      </button>
                    </div>
                  </div>
                )}
              </>
            )}

            {section === 'station' && (
              <>
                <h2 className="acct-h2">Station</h2>
                <div className="adm-field">
                  <p className="adm-field-label">Language for the station display</p>
                  <div className="adm-field-control">
                    {h.station.options.map((o) => (
                      <button
                        key={o.code}
                        className={`acct-seg${o.code === h.station.language ? ' is-on' : ''}`}
                        aria-pressed={o.code === h.station.language}
                        disabled={busy}
                        onClick={() => mutate('/admin/station', 'PATCH', { station: { language: o.code } })}
                      >
                        {o.name}
                      </button>
                    ))}
                  </div>
                </div>
              </>
            )}

            {section === 'content' && (
              <>
                <h2 className="acct-h2">Content</h2>
                <div className="adm-field">
                  <p className="adm-field-label">Species descriptions</p>
                  <p className="adm-field-hint">
                    Rebuild every bird&rsquo;s description. Runs in the background, a bird at a time.
                  </p>
                  <div className="adm-field-control">
                    <button
                      className="acct-seg"
                      disabled={busy}
                      onClick={() => mutate('/admin/species/refresh', 'POST', { refresh: true })}
                    >
                      Rebuild descriptions
                    </button>
                  </div>
                </div>

                <div className="adm-field">
                  <p className="adm-field-label">A note for the next letter</p>
                  <p className="adm-field-hint">
                    A line in your own voice, carried by the letter going out at {h.letter.at} and shown on
                    that day&rsquo;s journal entry. Say what is coming, not what has been. Leave it empty to
                    remove one.
                  </p>
                  <textarea
                    className="acct-select adm-note-box"
                    rows={3}
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    placeholder="The feeders are down for repairs tomorrow, so the garden may be quiet."
                    aria-label="note for the next letter"
                  />
                  <div className="adm-field-control">
                    <button
                      className="acct-seg"
                      disabled={busy}
                      onClick={() => mutate('/admin/note', 'PUT', { note })}
                    >
                      Save note
                    </button>
                  </div>
                </div>

                <div className="adm-field">
                  <p className="adm-field-label">Journal</p>
                  <p className="adm-field-hint">
                    Rebuild a completed day&rsquo;s journal. The letter is the same words.
                  </p>
                  <div className="adm-field-control">
                    <input
                      className="acct-select"
                      type="date"
                      value={journalDate}
                      onChange={(e) => setJournalDate(e.target.value)}
                      aria-label="journal date to rebuild"
                    />
                    <button
                      className="acct-seg"
                      disabled={busy || !journalDate}
                      onClick={() => mutate('/admin/journal/regenerate', 'POST', { date: journalDate })}
                    >
                      Rebuild journal
                    </button>
                  </div>
                </div>
              </>
            )}

            {section === 'email' && (
              <>
                <h2 className="acct-h2">Email</h2>
                <ul className="acct-rules">
                  <li className="acct-rule">
                    <span className="acct-rule-label">Goes out</span>
                    <span>
                      Every day at {h.letter.at} {h.letter.zone}
                    </span>
                  </li>
                  <li className="acct-rule">
                    <span className="acct-rule-label">Sending as</span>
                    <span className={delivery().warn ? 'adm-warn' : undefined}>{delivery().text}</span>
                  </li>
                </ul>

                <div className="adm-field adm-mt">
                  <p className="adm-field-label">A day&rsquo;s letter</p>
                  <p className="adm-field-hint">
                    Read it as a subscriber would, or send yourself a copy. Subscribers are only ever mailed
                    by the schedule above.
                  </p>
                  <div className="adm-field-control">
                    <input
                      className="acct-select"
                      type="date"
                      value={letterDate}
                      onChange={(e) => setLetterDate(e.target.value)}
                      aria-label="letter date"
                    />
                    <button
                      className="acct-seg"
                      disabled={!letterDate}
                      onClick={() =>
                        window.open(
                          `/admin/letter/preview?date=${encodeURIComponent(letterDate)}`,
                          '_blank',
                          'noopener',
                        )
                      }
                    >
                      Preview
                    </button>
                    <button
                      className="acct-seg"
                      disabled={busy || !letterDate || !h.alerts.configured}
                      onClick={() => mutate('/admin/letter/test', 'POST', { date: letterDate })}
                    >
                      Send to me
                    </button>
                  </div>
                </div>
              </>
            )}

            {section === 'broadcast' && (
              <>
                <h2 className="acct-h2">Broadcast</h2>
                <div className="adm-field">
                  <p className="adm-field-label">A one-off note to the letter&rsquo;s readers</p>
                  <p className="adm-field-hint">
                    For the times something needs saying — the station off for a fortnight, say. It goes to
                    the {h.letter.readers} {h.letter.readers === 1 ? 'person' : 'people'} on the daily letter,
                    and nobody else. Read it, send yourself a copy, then confirm.
                  </p>
                  <div className="adm-field-control">
                    <input
                      className="acct-select adm-blast-subject"
                      value={blastSubject}
                      onChange={(e) => editBlast(() => setBlastSubject(e.target.value))}
                      placeholder="Subject"
                      aria-label="broadcast subject"
                    />
                  </div>
                  <textarea
                    className="acct-select adm-note-box"
                    rows={5}
                    value={blastBody}
                    onChange={(e) => editBlast(() => setBlastBody(e.target.value))}
                    placeholder="The station is off for a fortnight while the mic is repaired. The journal will pick up again when it returns."
                    aria-label="broadcast body"
                  />
                  <div className="adm-field-control">
                    <button
                      className="acct-seg"
                      disabled={busy || !blastSubject.trim() || !blastBody.trim()}
                      onClick={() =>
                        fetch('/admin/blast/preview', {
                          method: 'POST',
                          headers: {
                            'Content-Type': 'application/json',
                            Accept: 'application/json',
                            'X-CSRF-Token': csrf(),
                          },
                          body: JSON.stringify({ subject: blastSubject, body: blastBody }),
                        })
                          .then((r) => r.json())
                          .then((j) => setBlastHtml(j.html ?? null))
                          .catch(() => setResult({ ok: false, message: 'Could not render the preview.' }))
                      }
                    >
                      Preview
                    </button>
                    <button
                      className="acct-seg"
                      disabled={busy || !blastSubject.trim() || !blastBody.trim() || !h.alerts.configured}
                      onClick={() =>
                        mutate('/admin/blast/test', 'POST', {
                          subject: blastSubject,
                          body: blastBody,
                        }).then((r) => setBlastTested(!!r?.ok))
                      }
                    >
                      Send to me
                    </button>
                  </div>
                </div>

                {blastHtml && (
                  <div className="adm-field">
                    <p className="adm-field-label">What they will get</p>
                    {/* srcDoc, not innerHTML: the email's own markup is rendered in an isolated
                        document so its styles can't leak into the console. */}
                    <iframe className="adm-blast-preview" title="Broadcast preview" srcDoc={blastHtml} />
                  </div>
                )}

                <div className="adm-zone">
                  <p className="adm-zone-h">Send to everyone</p>
                  <p className="adm-field-hint">
                    {blastTested
                      ? `Type ${h.letter.readers} to confirm. This cannot be unsent.`
                      : 'Send yourself a copy first — the send unlocks once one has landed.'}
                  </p>
                  <div className="adm-field-control">
                    <input
                      className="acct-select"
                      value={blastConfirm}
                      onChange={(e) => setBlastConfirm(e.target.value)}
                      placeholder={String(h.letter.readers)}
                      disabled={!blastTested}
                      aria-label="type the reader count to confirm"
                    />
                    <button
                      className="acct-seg adm-danger"
                      disabled={
                        busy ||
                        !blastTested ||
                        blastConfirm.trim() !== String(h.letter.readers) ||
                        !blastSubject.trim() ||
                        !blastBody.trim()
                      }
                      onClick={() =>
                        mutate('/admin/blast', 'POST', {
                          subject: blastSubject,
                          body: blastBody,
                          confirm: blastConfirm,
                        }).then((r) => {
                          if (r?.ok) editBlast(() => {})
                        })
                      }
                    >
                      Send to {h.letter.readers}
                    </button>
                  </div>
                </div>
              </>
            )}

            {section === 'danger' && (
              <div className="adm-zone">
                <p className="adm-zone-h">Danger zone</p>
                <p className="adm-field-label">Clear the detection history</p>
                <p className="adm-field-hint">
                  Removes every detection and everything derived from it. Species artwork and descriptions are
                  kept. This cannot be undone.
                </p>
                <div className="adm-field-control">
                  <input
                    className="acct-select"
                    value={confirm}
                    onChange={(e) => setConfirm(e.target.value)}
                    placeholder="DELETE"
                    aria-label="type DELETE to confirm"
                  />
                  <button
                    className="acct-seg adm-danger"
                    disabled={busy || confirm !== 'DELETE'}
                    onClick={() => mutate('/admin/data', 'DELETE', { confirm })}
                  >
                    Clear history
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </SidePanel>
  )
}
