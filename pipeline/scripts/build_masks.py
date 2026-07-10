#!/usr/bin/env python3
"""Rebuild the collage silhouette masks (masks.json) from the cutouts.

Step 3 of the illustration pipeline (after pregen.py and cutout.py).

The Rails collage packs birds by their actual silhouette, not bounding
boxes, so it ships a tiny 1-bit mask per illustration. This reads every
cutout in the illustrations dir and writes a standalone masks.json the
app reads directly:

    MASKS[slug] = {w, h, bits}  silhouette downscaled to <=93px, 1-bit
                  packed MSB-first row-major, base64. A bit is 1 where
                  the cutout is opaque (alpha > 127).

Usage:
    python3 build_masks.py            # write masks.json next to the cutouts
    python3 build_masks.py --check    # report counts only, don't write
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import sys
from pathlib import Path

from art import art_dir, masks_json

DIM_MAX = 560  # long side of the stored aspect
MASK_MAX = 93  # long side of the stored silhouette
ALPHA_ON = 127  # opaque above this -> silhouette bit set


def build_tables(illus_dir: Path):
    """Return (dims, masks) dicts keyed by slug, in sorted order."""
    from PIL import Image

    dims, masks = {}, {}
    pngs = sorted(p for p in illus_dir.glob("*.png") if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", p.stem))
    for p in pngs:
        slug = p.stem
        im = Image.open(p).convert("RGBA")
        w, h = im.size
        scale = DIM_MAX / max(w, h)
        dims[slug] = [round(w * scale), round(h * scale)]

        ms = MASK_MAX / max(w, h)
        mw, mh = max(1, round(w * ms)), max(1, round(h * ms))
        alpha = im.getchannel("A").resize((mw, mh), Image.LANCZOS)
        px = alpha.load()
        bits = bytearray((mw * mh + 7) // 8)
        for y in range(mh):
            for x in range(mw):
                if px[x, y] > ALPHA_ON:
                    i = y * mw + x
                    bits[i >> 3] |= 1 << (7 - (i & 7))
        masks[slug] = {"w": mw, "h": mh, "bits": base64.b64encode(bytes(bits)).decode()}
    return dims, masks


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--illustrations", type=Path, default=None, help="Cutout directory (default: $STATION_PROFILE/illustrations/)"
    )
    ap.add_argument(
        "--json", type=Path, default=None, help="Where to write masks.json (the Rails app reads this directly)"
    )
    ap.add_argument("--check", action="store_true", help="Report counts and don't write")
    args = ap.parse_args()
    args.illustrations = args.illustrations or art_dir()
    args.json = args.json or masks_json()

    dims, masks = build_tables(args.illustrations)
    perched = sum(1 for k in dims if not k.endswith("-2"))
    flight = sum(1 for k in dims if k.endswith("-2"))
    print(f"built {len(dims)} masks ({perched} perched + {flight} flight) from {args.illustrations}")
    if not dims:
        print("error: no cutouts found", file=sys.stderr)
        return 1

    if args.check:
        print(f"(check) would write {len(masks)} masks -> {args.json}")
        return 0

    args.json.write_text(json.dumps(masks, separators=(",", ":")))
    print(f"wrote {len(masks)} masks -> {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
