#!/usr/bin/env python3
"""Inky hardware self-test: push one finished bird image to the panel and exit.

Separates "is the panel wired and the driver OK?" from "does the app work?" — run
this first on the Pi, before the web app and the shooter, so day-one problems are
unambiguously hardware or unambiguously software, never both at once.

    uv run python shooter/inky_selftest.py                      # the robin
    uv run python shooter/inky_selftest.py path/to/bird.png
    uv run python shooter/inky_selftest.py --preview out.png    # no panel: dither to a PNG

Reuses the shooter's push_inky / dither, so it exercises the exact code path the
real frame push uses.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
PANEL_W, PANEL_H = 800, 480
DEFAULT_BIRD = REPO / "pipeline" / "assets" / "illustrations" / "erithacus-rubecula.png"


def matted(path: Path) -> Image.Image:
    """Centre the (transparent) bird on a panel-sized cream ground, like the collage."""
    bird = Image.open(path).convert("RGBA")
    bird.thumbnail((PANEL_W - 80, PANEL_H - 80))
    canvas = Image.new("RGBA", (PANEL_W, PANEL_H), (236, 234, 223, 255))
    canvas.alpha_composite(bird, ((PANEL_W - bird.width) // 2, (PANEL_H - bird.height) // 2))
    return canvas.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description="Push one bird image to the Inky panel and exit.")
    ap.add_argument("image", nargs="?", default=str(DEFAULT_BIRD), help="bird PNG (default: the robin)")
    ap.add_argument("--preview", metavar="PATH", help="no panel: write a Spectra-6 dither here instead")
    ap.add_argument("--rotate", type=int, default=0, choices=[0, 90, 180, 270], help="panel rotation")
    ap.add_argument("--saturation", type=float, default=0.6, help="Inky colour saturation 0-1")
    args = ap.parse_args()

    path = Path(args.image)
    if not path.exists():
        print(f"image not found: {path}", file=sys.stderr)
        return 1
    img = matted(path)

    sys.path.insert(0, str(REPO / "shooter"))
    if args.preview:
        from shoot import dither_spectra6  # noqa: PLC0415 — local, avoids importing inky

        dither_spectra6(img).save(args.preview)
        print(f"wrote preview {args.preview} (no panel pushed)")
        return 0

    from shoot import push_inky  # noqa: PLC0415 — lazy: only needs the Pi-only inky lib when pushing

    push_inky(img, saturation=args.saturation, rotate=args.rotate)
    print("pushed one bird to the Inky panel ✓  (if the colours look right, the wiring is good)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
