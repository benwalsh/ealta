import { useLang } from '../lang'
import type { Today } from '../types'
import { Sparkline } from './Sparkline'
import { WindowPicker } from './WindowPicker'

// The activity sparkline as its own quiet band between the collage and the TODAY
// text — the single live gesture. The time-window control sits in its head: it sets
// the graph's span (an hour to all-time) and the total beside it, and the ticks
// below rescale to match.
export function TodaySpark({
  today,
  windows,
  value,
  onChange,
  stickyTop,
}: {
  today: Today
  windows: [string, number][]
  value: number
  onChange: (hours: number) => void
  stickyTop?: number
}) {
  const { lang } = useLang()
  if (!today?.sparkline) return null

  const pick = (a: { en: string; ga: string }) => (lang === 'ga' ? a.ga : a.en)
  // Keep the extreme ticks inside the edges; centre the rest on their mark.
  const shift = (x: number) => (x <= 0 ? '0' : x >= 1 ? '-100%' : '-50%')

  return (
    <section className="today-spark" style={{ top: stickyTop }}>
      <div className="today-spark-head">
        {/* The window's total detections used to sit here; it now heads Recently heard as part
            of the shared stats line (detections · species · duration). */}
        <WindowPicker windows={windows} value={value} onChange={onChange} />
      </div>
      <Sparkline paths={today.sparkline} />
      <div className="today-anchors">
        {today.anchors.map((a, i) => (
          <span key={i} style={{ left: `${a.x * 100}%`, transform: `translateX(${shift(a.x)})` }}>
            {pick(a)}
          </span>
        ))}
      </div>
    </section>
  )
}
