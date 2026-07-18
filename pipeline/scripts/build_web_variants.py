#!/usr/bin/env python3
"""Render small WebP variants of the illustrations for the public website.

The device (the Pi + e-ink panel) wants the full-resolution PNG cutouts. The
website does not: the home-page collage draws each bird a couple of hundred
pixels wide, so shipping the ~540 KB source PNGs there means megabytes of art
for a paper-sized picture. This writes a plain, pre-sized `<slug>.webp` next to
each `<slug>.png`, so the website can address a ~40 KB file at a stable URL with
no on-the-fly resizing — the URL just resolves to a small file.

Keep WEB_WIDTH in step with CollagePresenter::CDN_WIDTH (dashboard) — that is the
width the collage asks for, and the width we render here.

Usage:
    python3 build_web_variants.py           # write missing/stale .webp variants
    python3 build_web_variants.py --force    # rewrite every variant
    python3 build_web_variants.py --check    # report what would change, write nothing
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from art import art_dir

WEB_WIDTH = 640  # long-side target, matched to CollagePresenter::CDN_WIDTH
QUALITY = 85  # WebP quality — quality-biased; a bird lands around ~40 KB


def variant_path(png: Path) -> Path:
    """The web variant sits beside its source: robin.png -> robin.webp."""
    return png.with_suffix(".webp")


def is_stale(png: Path, webp: Path) -> bool:
    """Regenerate when the variant is missing or older than its source PNG."""
    return not webp.exists() or webp.stat().st_mtime < png.stat().st_mtime


def render(png: Path, webp: Path) -> int:
    """Downscale-to-width and encode WebP (alpha preserved). Returns bytes written."""
    from PIL import Image

    im = Image.open(png).convert("RGBA")
    w, h = im.size
    if w > WEB_WIDTH:
        im = im.resize((WEB_WIDTH, round(h * WEB_WIDTH / w)), Image.LANCZOS)
    im.save(webp, "WEBP", quality=QUALITY, method=6)
    return webp.stat().st_size


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--illustrations", type=Path, default=None, help="Cutout directory (default: $STATION_PROFILE/illustrations/)"
    )
    ap.add_argument("--force", action="store_true", help="Rewrite every variant, not just missing/stale ones")
    ap.add_argument("--check", action="store_true", help="Report what would change and write nothing")
    args = ap.parse_args()
    illus_dir = args.illustrations or art_dir()

    pngs = sorted(p for p in illus_dir.glob("*.png") if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", p.stem))
    if not pngs:
        print(f"error: no illustrations found in {illus_dir}", file=sys.stderr)
        return 1

    todo = [p for p in pngs if args.force or is_stale(p, variant_path(p))]
    if args.check:
        print(f"(check) {len(todo)} of {len(pngs)} variants would be (re)written in {illus_dir}")
        return 0

    total = 0
    for png in todo:
        total += render(png, variant_path(png))
    fresh = len(pngs) - len(todo)
    print(f"wrote {len(todo)} WebP variants ({total // 1024} KB total) + {fresh} already fresh -> {illus_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
