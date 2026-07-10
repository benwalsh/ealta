import { useState } from 'react'
import type { CollageData } from '../types'

// The Ruby-packed collage: nodes come from /api/overview (CollagePresenter), we
// just draw them. Hover captions a bird; clicking opens its modal.
export function Collage({ data, onSelect }: { data: CollageData; onSelect: (sci: string) => void }) {
  const [cap, setCap] = useState<{ ga: string | null; en: string; count: number } | null>(null)

  return (
    <div className="ed-hero-collage">
      {/* Explicit width/height + aspect-ratio give the SVG a stable intrinsic size,
          so `height: auto` in a flex container can't collapse it to a line on a
          scroll-driven reflow. */}
      <svg
        className="collage"
        viewBox={`0 0 ${data.width} ${data.height}`}
        width={data.width}
        height={data.height}
        style={{ aspectRatio: `${data.width} / ${data.height}` }}
        xmlns="http://www.w3.org/2000/svg"
      >
        {data.species_count === 0 && (
          <text
            x={data.width / 2}
            y={data.height / 2}
            textAnchor="middle"
            fontStyle="italic"
            fontSize={30}
            fill="var(--ink-soft, #8b8b91)"
          >
            ag éisteacht…
          </text>
        )}
        {data.nodes.map((n, i) => (
          <g
            key={`${n.sci}-${i}`}
            className="collage__bird"
            style={{ cursor: 'pointer' }}
            onMouseEnter={() => setCap({ ga: n.ga, en: n.en, count: n.count })}
            onMouseLeave={() => setCap(null)}
            onClick={() => onSelect(n.sci)}
          >
            {n.image ? (
              <image
                href={n.image}
                x={n.cx - n.w / 2}
                y={n.cy - n.h / 2}
                width={n.w}
                height={n.h}
                preserveAspectRatio="xMidYMid meet"
                transform={n.flip ? `translate(${(n.cx * 2).toFixed(2)} 0) scale(-1 1)` : undefined}
              />
            ) : (
              <circle cx={n.cx} cy={n.cy} r={n.r} fill={n.fill} />
            )}
          </g>
        ))}
      </svg>
      <p className="ed-tip" aria-hidden={!cap}>
        {cap && (
          <>
            <span className="ct-name">{[cap.ga, cap.en].filter(Boolean).join(' · ')}</span>
            {' · '}
            <span className="ct-n">{cap.count.toLocaleString()}</span>{' '}
            <span className="ct-w">{cap.count === 1 ? 'call' : 'calls'}</span>
          </>
        )}
      </p>
    </div>
  )
}
