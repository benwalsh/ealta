import type { CollageNode } from '../types'

// The "greatest hits": once you scroll past the full collage, it locks into a
// horizontal line of the loudest birds, pinned below the masthead. Each stays
// clickable — the collage, distilled to a strip.

// The slot each bird is drawn into, in CSS pixels. Every image is `height: 42px; width: auto`
// in ink, so its WIDTH is unknown until the file lands — and in a centred flex row twelve
// unknown widths mean twelve boxes that jump sideways the moment they resolve. That was the
// whole of this page's 0.926 CLS: one shift, twelve culprits, all of them these images.
//
// So the box is reserved up front and the bird is contained inside it. The width can't come
// from the node (`w`/`h` describe the COLLAGE pose, while the strip prefers `perch_image` —
// a different drawing with its own aspect), so it is a fixed slot: wide enough for the
// broadest perched bird, with narrower ones centred in it. Uniform spacing is the trade, and
// on a row of twelve it reads as deliberate rather than as the ragged gaps it replaces.
const SLOT_W = 52
const SLOT_H = 42
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
          <img src={(n.perch_image ?? n.image)!} alt={n.en} width={SLOT_W} height={SLOT_H} />
        </button>
      ))}
    </div>
  )
}
