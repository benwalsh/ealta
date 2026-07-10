import type { CollageNode } from '../types'

// The "greatest hits": once you scroll past the full collage, it locks into a
// horizontal line of the loudest birds, pinned below the masthead. Each stays
// clickable — the collage, distilled to a strip.
export function HitsStrip({
  nodes,
  onSelect,
  pinned,
}: {
  nodes: CollageNode[]
  onSelect: (sci: string) => void
  pinned: boolean
}) {
  const hits = [...nodes]
    .filter((n) => n.image)
    .sort((a, b) => b.count - a.count)
    .slice(0, 12)

  if (!hits.length) return null

  return (
    <div className={`ed-hits${pinned ? ' is-on' : ''}`} aria-hidden={!pinned}>
      {hits.map((n) => (
        <button
          key={n.sci}
          className="ed-hit"
          title={n.en}
          tabIndex={pinned ? 0 : -1}
          onClick={() => onSelect(n.sci)}
        >
          <img src={(n.perch_image ?? n.image)!} alt={n.en} />
        </button>
      ))}
    </div>
  )
}
