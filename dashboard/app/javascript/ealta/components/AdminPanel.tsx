import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useHealth } from '../api'
import { ago, stamp } from '../time'
import { SidePanel } from './SidePanel'

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

type Result = { ok: boolean; message: string }

// The admin health console, docked. Read-only figures come from useHealth (polled); the
// station-language control and the maintenance actions POST/PATCH/DELETE with a CSRF
// header, show the server's { ok, message } inline (replacing the old flash), and
// invalidate ['health'] so the figures refresh. Closes itself if the fetch 403s.
export function AdminPanel({ onClose }: { onClose: () => void }) {
  const qc = useQueryClient()
  const { data: h, isError } = useHealth(true)
  const [result, setResult] = useState<Result | null>(null)
  const [busy, setBusy] = useState(false)

  // Maintenance form fields.
  const [detId, setDetId] = useState('')
  const [detSci, setDetSci] = useState('')
  const [confirm, setConfirm] = useState('')

  useEffect(() => {
    if (isError) onClose() // a non-admin's fetch 403s — nothing to show
  }, [isError, onClose])

  const mutate = (url: string, method: string, body?: object) => {
    setBusy(true)
    setResult(null)
    fetch(url, {
      method,
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrf() },
      body: body ? JSON.stringify(body) : undefined,
    })
      .then(async (r) => {
        const j = (await r.json().catch(() => null)) as Result | null
        setResult(j ?? { ok: r.ok, message: r.ok ? 'Done.' : `Error ${r.status}.` })
        qc.invalidateQueries({ queryKey: ['health'] })
      })
      .catch(() => setResult({ ok: false, message: 'Request failed.' }))
      .finally(() => setBusy(false))
  }

  const l = h?.listening
  const a = h?.alerts
  const s = h?.system

  return (
    <SidePanel title="Admin" width="wide" onClose={onClose}>
      {result && <p className={`adm-flash ${result.ok ? 'is-ok' : 'is-alert'}`}>{result.message}</p>}

      {h && l && a && s && (
        <>
          <section className="acct-sec">
            <h2 className="acct-h2">Station</h2>
            <p className="adm-lead">The wall speaks one language, consistently — pick which.</p>
            <div className="acct-cadence adm-mt">
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
          </section>

          <section className="acct-sec">
            <h2 className="acct-h2">Listening</h2>
            <p className="adm-lead">
              <span className={`adm-dot ${l.freshness}`} />
              {l.last_alive_at ? (
                <>
                  <span>Mic alive — last tick {ago(l.last_alive_at)} ago</span>
                  <span className="adm-abs">{stamp(l.last_alive_at)}</span>
                </>
              ) : l.last_heard_at ? (
                <>
                  <span>Last heard {ago(l.last_heard_at)} ago</span>
                  <span className="adm-abs">no heartbeat yet</span>
                </>
              ) : (
                <span>Nothing yet.</span>
              )}
            </p>
            {l.last_heard_at && (
              <p className="adm-note">
                Last bird {ago(l.last_heard_at)} ago{l.last_species ? ` — ${l.last_species.en}` : ''}. A
                heartbeat ticks every listening cycle, so the dot dims only when the mic → BirdNET loop
                actually stalls.
              </p>
            )}
            <div className="adm-stats">
              <div className="adm-stat">
                <span className="adm-fig">{l.detections_today.toLocaleString()}</span>
                <span className="adm-lbl">Detections today</span>
              </div>
              <div className="adm-stat">
                <span className="adm-fig">{l.detections_all_time.toLocaleString()}</span>
                <span className="adm-lbl">All-time</span>
              </div>
              <div className="adm-stat">
                <span className="adm-fig">{l.species_today}</span>
                <span className="adm-lbl">Species today</span>
              </div>
              <div className="adm-stat">
                <span className="adm-fig">{l.species_all_time}</span>
                <span className="adm-lbl">Species all-time</span>
              </div>
            </div>
          </section>

          <section className="acct-sec">
            <h2 className="acct-h2">Alerts</h2>
            <ul className="acct-rules">
              <li className="acct-rule">
                <span className="acct-rule-label">Delivery</span>
                <span>{a.configured ? `email · ${a.from}` : 'not configured'}</span>
              </li>
              <li className="acct-rule">
                <span className="acct-rule-label">Following / standing rules</span>
                <span>
                  {a.following} / {a.standing_rules}
                </span>
              </li>
              <li className="acct-rule">
                <span className="acct-rule-label">Events (pending)</span>
                <span className={a.events_pending > 0 ? 'adm-warn' : undefined}>
                  {a.events_total} ({a.events_pending})
                </span>
              </li>
              {a.last_event && (
                <li className="acct-rule">
                  <span className="acct-rule-label">Last event</span>
                  <span>
                    {a.last_event.type} · {a.last_event.name} · {ago(a.last_event.at)} ago
                  </span>
                </li>
              )}
            </ul>
          </section>

          <section className="acct-sec">
            <h2 className="acct-h2">System</h2>
            <ul className="acct-rules">
              <li className="acct-rule">
                <span className="acct-rule-label">Environment</span>
                <span>
                  {s.env} · {s.adapter}
                </span>
              </li>
              <li className="acct-rule">
                <span className="acct-rule-label">Site</span>
                <span>{s.site_url || '—'}</span>
              </li>
              <li className="acct-rule">
                <span className="acct-rule-label">LLM region</span>
                <span>{s.llm_region || '—'}</span>
              </li>
              <li className="acct-rule">
                <span className="acct-rule-label">Offsite backup</span>
                <span>{s.backup.configured ? `Litestream · ${s.backup.bucket}` : 'not configured'}</span>
              </li>
            </ul>
          </section>

          <section className="acct-sec">
            <h2 className="acct-h2">Maintenance</h2>
            <p className="adm-lead">
              Restart the detection listener if it wedges. Off the Pi this does nothing.
            </p>
            <div className="adm-mt">
              <button
                className="acct-seg"
                disabled={busy}
                onClick={() => mutate('/admin/birdnet/restart', 'POST')}
              >
                Restart listener
              </button>
            </div>

            <p className="adm-lead adm-mt">Relabel a mis-identified detection to the correct species.</p>
            <div className="acct-add adm-mt">
              <input
                className="acct-select"
                value={detId}
                onChange={(e) => setDetId(e.target.value)}
                placeholder="detection id"
                aria-label="detection id"
              />
              <input
                className="acct-select"
                value={detSci}
                onChange={(e) => setDetSci(e.target.value)}
                placeholder="scientific name"
                aria-label="scientific name"
              />
              <button
                className="acct-seg"
                disabled={busy || !detId || !detSci}
                onClick={() =>
                  mutate('/admin/detection', 'PATCH', { detection: { id: detId, sci_name: detSci } })
                }
              >
                Relabel
              </button>
            </div>

            <p className="adm-lead adm-mt">
              Clear the detection history (keeps enrichment caches). Type DELETE to confirm.
            </p>
            <div className="acct-add adm-mt">
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
                Clear data
              </button>
            </div>
          </section>
        </>
      )}
    </SidePanel>
  )
}
