import { useEffect, useState } from 'react'
import { useLang } from '../lang'
import type { Bootstrap, Tab } from '../types'
import { AccountMenu } from './AccountMenu'

// icon = the phone fallback (the word is hidden below 560px; see editorial.css).
const TABS: { id: Tab; en: string; ga: string; icon: string }[] = [
  { id: 'live', en: 'Live', ga: 'Beo', icon: 'ti-feather' },
  { id: 'journal', en: 'Journal', ga: 'Dialann', icon: 'ti-notebook' },
  { id: 'stats', en: 'Stats', ga: 'Sonraí', icon: 'ti-chart-bar' },
  { id: 'directory', en: 'Directory', ga: 'Eolaí', icon: 'ti-book-2' },
]

interface MastheadProps {
  bootstrap: Bootstrap
  tab: Tab
  onTab: (t: Tab) => void
  onOpenAccount: () => void
}

export function Masthead({ bootstrap, tab, onTab, onOpenAccount }: MastheadProps) {
  const { lang, setLang, t } = useLang()
  // The masthead is sticky and condenses once the page scrolls, so the logo + nav
  // stay to hand without the full-height header eating the viewport.
  const [scrolled, setScrolled] = useState(false)
  useEffect(() => {
    // Hysteresis: condensing shortens the header, which nudges scrollY back across a single
    // threshold and oscillates (flicker). A dead-band — condense past 56, expand only under
    // 8 — means the crossing can't feed back on itself.
    const onScroll = () => setScrolled((prev) => (prev ? window.scrollY > 8 : window.scrollY > 56))
    window.addEventListener('scroll', onScroll, { passive: true })
    onScroll()
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <header className={`ed-topbar${scrolled ? ' is-scrolled' : ''}`}>
      <div className="ed-top">
        <button className="ed-brand" onClick={() => onTab('live')}>
          {bootstrap.assets.mark && (
            <img
              className="ed-mark"
              src={bootstrap.assets.mark}
              alt={t(bootstrap.assets.mark_alt.en, bootstrap.assets.mark_alt.ga)}
              width={52}
              height={46}
            />
          )}
          <span className="ed-word">{bootstrap.site_name}</span>
        </button>
        <nav className="ed-nav" aria-label="Sections">
          {TABS.map((t) => {
            const label = lang === 'ga' ? t.ga : t.en
            return (
              <button
                key={t.id}
                className="ed-navitem"
                aria-current={tab === t.id ? 'page' : undefined}
                aria-label={label}
                onClick={() => onTab(t.id)}
              >
                <i className={`ti ${t.icon}`} aria-hidden="true" />
                <span className="ed-navitem-label">{label}</span>
              </button>
            )
          })}
          <div className="ed-lang" role="group" aria-label="Language">
            <button className={`ed-lang-opt${lang === 'en' ? ' is-on' : ''}`} onClick={() => setLang('en')}>
              EN
            </button>
            <button className={`ed-lang-opt${lang === 'ga' ? ' is-on' : ''}`} onClick={() => setLang('ga')}>
              GA
            </button>
          </div>
          <AccountMenu user={bootstrap.current_user} onOpenAccount={onOpenAccount} />
        </nav>
      </div>
    </header>
  )
}
