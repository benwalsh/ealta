import type { SparkPaths } from '../types'

// The single live gesture on the paper. The path maths is done in Ruby (see Sparkline
// service); this just prints the two path strings.
//
// Blind spots are shown by ABSENCE, not by furniture. Where the mic was down the curve is
// split into separate runs, so the line simply stops and resumes; where it was down all
// window there is no path at all. A grey slab and a "No data · 06:00–08:48" label used to
// be painted over the gap, which was the loudest thing on a page whose whole manner is
// quiet — and it had to shout precisely because a resting line was drawn underneath it.
// Draw nothing, and nothing needs explaining: a break reads as a break, never as a zero.
// `muted` renders the curve stilled and greyscale (no fill) — the Journal's finished-day
// twin of Live's living green line.
export function Sparkline({ paths, muted = false }: { paths: SparkPaths; muted?: boolean }) {
  const { path, fill, w, h } = paths

  return (
    <div className={`today-spark-plot${muted ? ' is-muted' : ''}`}>
      <svg
        className="today-spark-svg"
        viewBox={`0 0 ${w} ${h}`}
        width={w}
        height={h}
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        <defs>
          <linearGradient id="spark-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--green)" stopOpacity="0.18" />
            <stop offset="1" stopColor="var(--green)" stopOpacity="0" />
          </linearGradient>
        </defs>
        <path d={fill} className="today-spark-fill" fill="url(#spark-fill)" stroke="none" />
        <path d={path} fill="none" className="today-spark-line" />
      </svg>
    </div>
  )
}
