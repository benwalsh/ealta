import { useLang } from '../lang'
import type { SparkPaths } from '../types'

// The single live gesture on the paper. The path maths is done in Ruby (see Sparkline
// service); this prints the two path strings, plus — where the mic was down — a pale
// "no data" band with a centred label, so a blind spot reads as an explicit
// data-availability state, never a false flat-zero. The band is an SVG rect (scales
// with the stretched viewBox); its label is an HTML overlay so the non-uniform scale
// can't distort the type.
// `muted` renders the curve stilled and greyscale (no fill) — the Journal's finished-day
// twin of Live's living green line.
export function Sparkline({ paths, muted = false }: { paths: SparkPaths; muted?: boolean }) {
  const { lang } = useLang()
  const { path, fill, gaps, w, h } = paths
  const pick = (a: { en: string; ga: string }) => (lang === 'ga' ? a.ga : a.en)
  const pct = (x: number) => `${(x / w) * 100}%`

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
        {/* Blind spots first, behind the chart: a pale neutral band over the real span. */}
        {gaps?.map((g, i) => (
          <rect key={i} className="today-spark-gap" x={g.x0} y="0" width={g.x1 - g.x0} height={h} />
        ))}
        <path d={fill} className="today-spark-fill" fill="url(#spark-fill)" stroke="none" />
        <path d={path} fill="none" className="today-spark-line" />
      </svg>
      {gaps?.map((g, i) => (
        <span key={i} className="today-spark-gap-label" style={{ left: pct(g.x0), width: pct(g.x1 - g.x0) }}>
          <span className="gap-full">{pick(g.label)}</span>
          <span className="gap-short">{pick(g.short)}</span>
        </span>
      ))}
    </div>
  )
}
