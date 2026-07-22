import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useOverview } from '../api'
import { useLang } from '../lang'
import { useFollow } from '../favourites'
import { Collage } from './Collage'
import { HitsStrip } from './HitsStrip'
import { TodaySpark } from './TodaySpark'
import { AlmanacRow } from './AlmanacRow'
import { NotableBlock } from './NotableBlock'
import { LiveLists } from './LiveLists'
import { DetectionStats } from './DetectionStats'
import type { NotableItem } from '../types'

// The condensed masthead's height — the hits strip pins just under it (see .ed-hits
// top:54px), and the sparkline/almanac stack below the hits strip from there.
const MAST_H = 54

// Live: present tense, ambient. The collage, the live sparkline & window picker, the
// almanac — then New & notable. Scroll past the collage and the three strips lock and
// stack under the masthead; New & notable scrolls beneath. The warm, narrated story of a
// completed day lives on the Journal tab, not here.
export function LiveTab({
  onSelect,
  windowHours,
  onWindow,
  windows,
}: {
  onSelect: (sci: string) => void
  windowHours: number
  onWindow: (hours: number) => void
  windows: [string, number][]
}) {
  const { data, isLoading, isError } = useOverview(windowHours)
  const { t } = useLang()
  const { enabled, following } = useFollow()
  const stageRef = useRef<HTMLElement>(null)
  const [pinned, setPinned] = useState(false)
  // The three strips lock and stack under the masthead as you scroll: the collage's hits strip
  // first, then the sparkline sticks below it, then the almanac below that. These are the sticky
  // `top` offsets — each the running height of the strips above it, measured from what's actually
  // rendered (responsive), so the stack is always flush whatever the heights come out to.
  const [stack, setStack] = useState({ spark: MAST_H, almanac: MAST_H })

  // Pin the hits strip once the collage has scrolled up past the (condensed) masthead.
  useEffect(() => {
    const onScroll = () => {
      const stage = stageRef.current
      if (stage) setPinned(stage.getBoundingClientRect().bottom < 72)
    }
    window.addEventListener('scroll', onScroll, { passive: true })
    onScroll()
    return () => window.removeEventListener('scroll', onScroll)
  }, [data])

  // Measure the stack: sparkline below masthead + hits; almanac below both. Re-run on data and
  // resize. offsetHeight is unaffected by the strips' own sticky state, so it reads right.
  useLayoutEffect(() => {
    const measure = () => {
      const h = (sel: string) => (document.querySelector(sel) as HTMLElement | null)?.offsetHeight ?? 0
      const hits = h('.ed-hits')
      const spark = h('.today-spark')
      setStack({ spark: MAST_H + hits, almanac: MAST_H + hits + spark })
    }
    measure()
    window.addEventListener('resize', measure)
    return () => window.removeEventListener('resize', measure)
  }, [data])

  // The waiting state RESERVES the collage's box rather than collapsing to a line of dots.
  // /api/overview gates the whole view, so this placeholder is what the first paint shows;
  // swapping a ~140px stub for the ~780px real thing moved the entire page under the reader
  // and was measured as a 0.93 layout shift — nearly a full viewport, and the thing that made
  // the page *feel* slow even once the images themselves were arriving quickly.
  // The box is reserved in CSS (.ed-stage-waiting) via the collage's fixed 800×480 aspect, so
  // it matches at every width without this component knowing the viewport.
  if (isLoading || !data) {
    return (
      <section className="ed-stage is-waiting" aria-busy={!isError}>
        <div className="ed-stage-waiting">{isError ? '—' : '…'}</div>
      </section>
    )
  }

  // Your favourites: the signed-in reader's followed birds that were actually heard in
  // this window — the collage nodes are exactly that set. Computed client-side so the
  // cacheable, cookie-free /api/overview stays personalisation-free.
  const favourites: NotableItem[] = enabled
    ? data.collage.nodes.filter((n) => following(n.sci)).map((n) => ({ sci: n.sci, en: n.en, ga: n.ga }))
    : []

  return (
    <>
      <HitsStrip nodes={data.collage.nodes} onSelect={onSelect} pinned={pinned} />

      <section className="ed-stage" ref={stageRef}>
        <Collage data={data.collage} onSelect={onSelect} status={data.status} />
      </section>

      {/* Sparkline (listening status) + almanac (weather/tide/sun/moon) are NOT about
          heard birds — they must show even in an empty window. Only the heard-birds
          lists collapse to the quiet-window message. */}
      <TodaySpark
        today={data.today}
        windows={windows}
        value={windowHours}
        onChange={onWindow}
        stickyTop={stack.spark}
      />
      <AlmanacRow today={data.today} status={data.status} stickyTop={stack.almanac} />
      {data.collage.nodes.length ? (
        <>
          <NotableBlock groups={data.notable} favourites={favourites} onSelect={onSelect} />
          <DetectionStats
            detections={data.stats.detections}
            species={data.stats.species}
            durationSeconds={data.stats.duration_seconds}
          />
          <LiveLists recent={data.recent} onSelect={onSelect} />
        </>
      ) : data.status === 'offline' ? (
        <p className="ed-empty">{t('As líne — the mic is quiet.', 'As líne — tá an micreafón ina thost.')}</p>
      ) : (
        <p className="ed-empty">{t('Ag éisteacht… nothing heard yet.', 'Ag éisteacht… faic cloiste fós.')}</p>
      )}
    </>
  )
}
