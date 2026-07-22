import { useLang } from '../lang'
import { ago } from '../time'
import type { Tally } from '../types'
import { HeardList } from './HeardList'

// Live's reading body: Recently heard — the window's birds, freshest first, with
// time-ago. The present-tense counterpart to the collage (which is *which* birds; this
// is *when*). Rankings, life list and first-seen deliberately live on Stats, not here.
// The Journal renders the same HeardList locked to one finished day, saying the clock
// time instead of the elapsed one.
export function LiveLists({ recent, onSelect }: { recent: Tally[]; onSelect: (sci: string) => void }) {
  const { t, lang } = useLang()

  return (
    <HeardList
      title={t('Recently heard', 'Cloiste le déanaí')}
      heard={recent}
      meta={(r) => ago(r.last_time, lang)}
      onSelect={onSelect}
    />
  )
}
