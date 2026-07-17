import { useEffect, useState } from 'react'
import { useLang } from '../lang'
import { useFollow } from '../favourites'
import { useAccount } from '../api'
import { SidePanel } from './SidePanel'
import type { CurrentUser } from '../types'

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

// The account side-panel: identity, the daily-letter toggle, and the followed species.
// The follow list is driven entirely by the FollowProvider (the same state the Directory
// checkboxes use) — this panel just resolves those sci_names to names from the picker
// list. Reuses the .acct-* design-system classes the server page already carried.
export function AccountPanel({
  user,
  onClose,
  onOpenAdmin,
}: {
  user: CurrentUser
  onClose: () => void
  onOpenAdmin: () => void
}) {
  const { t, lang } = useLang()
  const { followed, toggle } = useFollow()
  const { data } = useAccount(true)

  const names = new Map((data?.species ?? []).map((s) => [s.sci, s]))
  const follows = followed
    .map((sci) => names.get(sci) ?? { sci, en: sci, ga: null })
    .sort((a, b) => a.en.localeCompare(b.en))

  // The daily letter (roundup) — a local optimistic mirror of the server state, confirmed
  // or reverted by the toggle's JSON reply so the checkbox never lies about a write.
  const [roundup, setRoundup] = useState(false)
  useEffect(() => {
    if (data) setRoundup(data.roundup)
  }, [data])

  const setLetter = (on: boolean) => {
    setRoundup(on)
    fetch('/subscriptions/cadence', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrf() },
      body: JSON.stringify({ alert_type: 'roundup', cadence: on ? 'digest' : 'off' }),
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((j) => setRoundup(!!j.roundup))
      .catch(() => setRoundup(!on))
  }

  return (
    <SidePanel title={t('Account', 'Cuntas')} width="slim" onClose={onClose}>
      <section className="acct-me">
        {user.avatar_url ? (
          <img className="acct-avatar" src={user.avatar_url} alt={user.name} referrerPolicy="no-referrer" />
        ) : (
          <span className="acct-avatar acct-avatar-initial">{user.name.trim().charAt(0).toUpperCase()}</span>
        )}
        <div className="acct-me-id">
          <span className="acct-me-name">{user.name}</span>
          {user.email && user.email !== user.name && <span className="acct-me-email">{user.email}</span>}
        </div>
        {user.admin && (
          <button className="acct-link acct-me-admin" onClick={onOpenAdmin}>
            {t('Admin', 'Riarachán')}
          </button>
        )}
      </section>

      <section className="acct-sec">
        <h2 className="acct-h2">{t('The daily letter', 'An litir laethúil')}</h2>
        <p className="acct-note">
          {t(
            "The day's journal, by email, just after midnight.",
            'Dialann an lae, ar ríomhphost, díreach tar éis meán oíche.',
          )}
        </p>
        <ul className="acct-rules">
          <li className="acct-rule">
            <span className="acct-rule-label">{t('Daily letter', 'Litir laethúil')}</span>
            <label className="acct-cadence acct-check">
              <input
                className="acct-check-input"
                type="checkbox"
                checked={roundup}
                onChange={(e) => setLetter(e.target.checked)}
                aria-label={t('Daily letter', 'Litir laethúil')}
              />
              <span className="acct-check-box" />
            </label>
          </li>
        </ul>
      </section>

      <section className="acct-sec">
        <h2 className="acct-h2">{t("Species you're following", 'Speicis a leanann tú')}</h2>
        {follows.length > 0 ? (
          <ul className="acct-list">
            {follows.map((f) => {
              const primary = lang === 'ga' && f.ga ? f.ga : f.en
              const secondary = lang === 'ga' ? f.en : f.ga
              return (
                <li className="acct-item" key={f.sci}>
                  <span className="acct-name">{primary}</span>
                  {secondary && secondary !== primary && <span className="acct-ga">{secondary}</span>}
                  <button className="acct-btn acct-remove" onClick={() => toggle(f.sci)}>
                    {t('Unfollow', 'Ná lean')}
                  </button>
                </li>
              )
            })}
          </ul>
        ) : (
          <p className="acct-empty">
            {t("You're not following any species yet.", 'Níl tú ag leanúint aon speiceas fós.')}
          </p>
        )}
        <div className="acct-add">
          <select
            className="acct-select"
            value=""
            aria-label={t('Follow a species', 'Lean speiceas')}
            onChange={(e) => e.target.value && toggle(e.target.value)}
          >
            <option value="">{t('Choose a species…', 'Roghnaigh speiceas…')}</option>
            {(data?.species ?? [])
              .filter((s) => !followed.includes(s.sci))
              .map((s) => (
                <option key={s.sci} value={s.sci}>
                  {s.ga ? `${s.en} · ${s.ga}` : s.en}
                </option>
              ))}
          </select>
        </div>
      </section>

      <footer className="acct-foot">
        <form method="post" action="/logout">
          <input type="hidden" name="_method" value="delete" />
          <input type="hidden" name="authenticity_token" value={csrf()} />
          <button className="acct-link" type="submit">
            {t('Sign out', 'Logáil amach')}
          </button>
        </form>
      </footer>
    </SidePanel>
  )
}
