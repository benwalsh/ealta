import { useState } from 'react'
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
  const [tab, setTabState] = useState<Tab>(initialTab)
  const [win, setWin] = useState<number>(24) // time window in hours (Live/Stats)
  const [selected, setSelected] = useState<string | null>(null)

  const setTab = (t: Tab) => {
    setTabState(t)
    const url = t === 'live' ? window.location.pathname : `${window.location.pathname}?tab=${t}`
    window.history.replaceState(null, '', url)
  }

  return (
    <QueryClientProvider client={queryClient}>
      <LangProvider initial={bootstrap.ui_lang}>
        <FollowProvider enabled={!!bootstrap.current_user} initial={bootstrap.favourites ?? []}>
          <Masthead bootstrap={bootstrap} tab={tab} onTab={setTab} />
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
        </FollowProvider>
      </LangProvider>
    </QueryClientProvider>
  )
}
