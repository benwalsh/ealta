import { useEffect, useState } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { Bootstrap, Tab } from './types'
import { LangProvider } from './lang'
import { FollowProvider } from './favourites'
import { Masthead } from './components/Masthead'
import { Footer } from './components/Footer'
import { LiveTab } from './components/LiveTab'
import { JournalTab } from './components/JournalTab'
import { StatsTab } from './components/StatsTab'
import { DirectoryTab } from './components/DirectoryTab'
import { SpeciesModal } from './components/SpeciesModal'
import { AccountPanel } from './components/AccountPanel'
import { AdminPanel } from './components/AdminPanel'

type Panel = 'account' | 'admin' | null

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 30_000, refetchOnWindowFocus: false, retry: 1 } },
})

const TABS: Tab[] = ['live', 'journal', 'stats', 'directory']

function initialTab(): Tab {
  const t = new URLSearchParams(window.location.search).get('tab')
  if (t === 'birds') return 'live' // legacy ?tab=birds link → Live
  return TABS.includes(t as Tab) ? (t as Tab) : 'live'
}

export function App({ bootstrap }: { bootstrap: Bootstrap }) {
  const [tab, setTab] = useState<Tab>(initialTab)
  const [win, setWin] = useState<number>(24) // time window in hours (Live/Stats)
  const [selected, setSelected] = useState<string | null>(null)
  // The docking side-panels. Seeded from the bootstrap so a hard nav to /account or
  // /admin boots the SPA with that panel already open (deep-link).
  const [panel, setPanel] = useState<Panel>(bootstrap.open_panel ?? null)

  // One place owns the URL: /account or /admin while a panel is open, otherwise the tab
  // URL (mirroring the old ?tab= scheme). replaceState — never pushState — so Back isn't
  // trapped cycling a panel open and shut.
  useEffect(() => {
    const url =
      panel === 'account' ? '/account' : panel === 'admin' ? '/admin' : tab === 'live' ? '/' : `/?tab=${tab}`
    window.history.replaceState(null, '', url)
  }, [panel, tab])

  const user = bootstrap.current_user

  return (
    <QueryClientProvider client={queryClient}>
      <LangProvider initial={bootstrap.ui_lang}>
        <FollowProvider enabled={!!user} initial={bootstrap.favourites ?? []}>
          <Masthead
            bootstrap={bootstrap}
            tab={tab}
            onTab={setTab}
            onOpenAccount={() => setPanel('account')}
          />
          <main className="ed-main">
            {tab === 'live' && (
              <LiveTab
                onSelect={setSelected}
                windowHours={win}
                onWindow={setWin}
                windows={bootstrap.windows}
              />
            )}
            {tab === 'journal' && <JournalTab onSelect={setSelected} />}
            {tab === 'stats' && (
              <StatsTab
                onSelect={setSelected}
                windowHours={win}
                onWindow={setWin}
                windows={bootstrap.windows}
              />
            )}
            {tab === 'directory' && <DirectoryTab onSelect={setSelected} />}
          </main>
          <Footer place={bootstrap.place} siteName={bootstrap.site_name} />
          {selected && <SpeciesModal sci={selected} onClose={() => setSelected(null)} />}
          {panel === 'account' && user && (
            <AccountPanel user={user} onClose={() => setPanel(null)} onOpenAdmin={() => setPanel('admin')} />
          )}
          {panel === 'admin' && (
            <AdminPanel
              onClose={() => setPanel(null)}
              onBack={user ? () => setPanel('account') : undefined}
            />
          )}
        </FollowProvider>
      </LangProvider>
    </QueryClientProvider>
  )
}
