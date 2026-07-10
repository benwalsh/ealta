#!/usr/bin/env python3
"""Light-weight background removal for the generated illustrations.

pregen.py renders each bird on a flat cream ground; this lifts that ground to
transparency with a border flood-fill, drops any stray flecks the flood leaves
behind, and crops to the bird. Pillow + numpy + scipy — no rembg/onnxruntime,
which conflict with the BirdNET stack in our shared env. The edges are softer
than BiRefNet matting, but at dashboard/atlas size it reads clean. Already-cut
files are skipped unless you pass --force (re-cut) or --declutter (just sweep
the flecks from an existing cutout, non-destructively).

    uv run python pipeline/scripts/cutout_flood.py             # cut uncut illustrations
    uv run python pipeline/scripts/cutout_flood.py --force     # re-cut everything
    uv run python pipeline/scripts/cutout_flood.py --declutter # sweep flecks from existing cutouts
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from art import art_dir
from PIL import Image, ImageDraw
from scipy import ndimage

DIR = art_dir()
SENTINEL = (0, 255, 1)  # a colour the art won't contain
THRESH = 46  # flood tolerance around each border seed's ground colour
MARGIN = 0.02  # crop padding, as a fraction of the bird's larger side
ALPHA_ON = 24  # alpha above this counts as ink when finding the bird
BRIDGE = 3  # px of dilation to bridge thin gaps (legs, beak) into the body
# A stray fleck is the leftover ground stipple: light and desaturated (warm
# beige). A real detail floating free of the body (a pale bird's eye sits in its
# transparent white head) is darker or more saturated, so we never drop those.
STIPPLE_BRIGHT = 150  # mean RGB brightness above this...
STIPPLE_SAT = 55  # ...and (max-min) channel spread below this => ground fleck
KEEP_NEAR = 0.04  # also keep any fleck within this fraction of the long side
#                         of the body (protects pale legs/details touching it)


def is_transparent(img: Image.Image) -> bool:
    return img.mode == "RGBA" and img.getchannel("A").getextrema()[0] == 0


def border_seeds(w: int, h: int) -> set[tuple[int, int]]:
    """Seed points all around the frame, not just the four corners — a cream
    ground that shades across the image leaves mid-edge bands the corner seeds
    can't reach (those drifted bands are where the left-hand smudges came from)."""
    xs = [1, w // 4, w // 2, 3 * w // 4, w - 2]
    ys = [1, h // 4, h // 2, 3 * h // 4, h - 2]
    seeds = {(x, 1) for x in xs} | {(x, h - 2) for x in xs}
    seeds |= {(1, y) for y in ys} | {(w - 2, y) for y in ys}
    return seeds


def despeckle(arr: np.ndarray) -> np.ndarray:
    """Sweep the leftover ground stipple, but never a real detail. Bridge thin
    gaps, find the bird's main blob, then drop each *other* blob only if it is
    BOTH ground-coloured (light, desaturated beige) AND well clear of the body —
    so a pale bird's free-floating eye or legs survive, while corner flecks go."""
    solid = arr[:, :, 3] > ALPHA_ON
    if not solid.any():
        return arr
    bridged = ndimage.binary_dilation(solid, iterations=BRIDGE)
    labels, count = ndimage.label(bridged)
    if count <= 1:
        return arr

    areas = np.bincount(labels.ravel())
    areas[0] = 0  # ignore the transparent background
    body = int(areas.argmax())
    near = ndimage.distance_transform_edt(labels != body) <= max(arr.shape[:2]) * KEEP_NEAR

    keep = labels == body
    for idx in range(1, count + 1):
        if idx == body:
            continue
        blob = labels == idx
        rgb = arr[blob & solid][:, :3].mean(axis=0)
        stipple = rgb.mean() > STIPPLE_BRIGHT and (rgb.max() - rgb.min()) < STIPPLE_SAT
        if stipple and not (blob & near).any():
            continue  # ground fleck, clear of the body -> drop
        keep |= blob  # a real detail (dark/coloured) or one hugging the body -> keep
    arr[~keep] = (0, 0, 0, 0)
    return arr


def save_cropped(arr: np.ndarray, path: Path) -> None:
    rgba = Image.fromarray(arr, "RGBA")
    w, h = rgba.size
    bbox = rgba.getchannel("A").getbbox()
    if bbox:
        pad = round(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * MARGIN)
        bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(w, bbox[2] + pad), min(h, bbox[3] + pad))
        rgba = rgba.crop(bbox)
    rgba.save(path)


def cut(path: Path) -> bool:
    rgb = Image.open(path).convert("RGB")
    w, h = rgb.size
    for seed in border_seeds(w, h):
        ImageDraw.floodfill(rgb, seed, SENTINEL, thresh=THRESH)
    arr = np.array(rgb.convert("RGBA"))
    ground = (arr[:, :, 0] == SENTINEL[0]) & (arr[:, :, 1] == SENTINEL[1]) & (arr[:, :, 2] == SENTINEL[2])
    arr[ground] = (0, 0, 0, 0)
    save_cropped(despeckle(arr), path)
    return True


def declutter(path: Path) -> bool:
    """Sweep flecks from an already-transparent cutout, in place. Returns False
    if there was nothing to sweep (so it's safe to run across the whole set)."""
    arr = np.array(Image.open(path).convert("RGBA"))
    before = int((arr[:, :, 3] > ALPHA_ON).sum())
    arr = despeckle(arr)
    if int((arr[:, :, 3] > ALPHA_ON).sum()) == before:
        return False
    save_cropped(arr, path)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description="Flood-fill background removal for illustrations.")
    ap.add_argument("--force", action="store_true", help="re-cut already-transparent files")
    ap.add_argument(
        "--declutter", action="store_true", help="sweep stray flecks from existing cutouts (non-destructive)"
    )
    args = ap.parse_args()

    done = skipped = 0
    for path in sorted(DIR.glob("*.png")):
        transparent = is_transparent(Image.open(path))
        if args.declutter:
            # Sweep flecks from good cutouts only; leave uncut grounds for a re-cut.
            done += declutter(path) if transparent else 0
            skipped += 0 if transparent else 1
        elif transparent and not args.force:
            skipped += 1
        else:
            cut(path)
            done += 1
    verb = "swept" if args.declutter else "cut"
    print(f"{verb} {done} · skipped {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
