#!/usr/bin/env python3
"""Zero-config default illustrations — a Wikipedia photo per bird, made panel-ready with no
model prompt and no API key.

For each species: fetch the Wikipedia lead photo (pregen.ensure_reference), matte out the
background (BiRefNet via rembg), crop to the bird, and dither to the six Spectra-6 inks — the
palette the e-ink panel uses — so a photograph reads as ink-on-paper rather than a snapshot.
One perched pose per bird (``<slug>.png``) into the station profile's ``illustrations/`` dir;
run ``build_masks.py`` afterwards to refresh the collage silhouettes.

This is the FREE DEFAULT tier: it is what ``make regen`` runs when ``GEMINI_API_KEY`` is unset,
so a freshly cloned station has real bird pictures out of the box. A station that sets a key
uses ``pregen.py`` instead for bespoke kachō-e linocut art. Deterministic; offline after the
Wikipedia fetch and the one-time BiRefNet model download.

Usage:
    python3 flatgen.py --labels ~/BirdNET-Pi/model/labels.txt      # the whole label set
    python3 flatgen.py --species "Turdus merula|Eurasian Blackbird" # one bird
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from art import art_dir
from pregen import ensure_reference, parse_species_list, slugify

# Mirrors shooter/shoot.py's SPECTRA6 — the six approximate panel inks. Kept in step with that
# file by hand; folding both onto one shared constant is a fair future tidy-up.
SPECTRA6 = [(236, 234, 223), (26, 26, 28), (165, 60, 56), (198, 176, 74), (49, 71, 130), (58, 110, 72)]


def dither_to_spectra6(rgba, saturation: float = 0.6):
    """Floyd–Steinberg dither the colour to the six inks, preserving the cutout's alpha.

    The panel mutes colour by ``saturation`` on hardware; we mirror that so a busy photo does
    not spray coloured speckle into near-neutral feathers. Alpha is lifted out before the
    quantise (which is RGB-only) and re-applied after, so the transparent ground survives.
    """
    from PIL import Image, ImageEnhance

    alpha = rgba.getchannel("A")
    rgb = rgba.convert("RGB")
    if saturation < 1.0:
        rgb = ImageEnhance.Color(rgb).enhance(saturation)
    pal = Image.new("P", (1, 1))
    flat = [c for ink in SPECTRA6 for c in ink]
    flat += list(SPECTRA6[0]) * ((768 - len(flat)) // 3)
    pal.putpalette(flat[:768])
    dithered = rgb.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG).convert("RGBA")
    dithered.putalpha(alpha)
    return dithered


def species_from(args) -> list[tuple[str, str]]:
    lines = [args.species] if args.species else Path(args.labels).read_text().splitlines()
    parsed, _ = parse_species_list(lines)
    return parsed[: args.limit] if args.limit else parsed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--labels", type=Path, help="BirdNET labels file (one 'Sci_Common' per line)")
    src.add_argument("--species", help='One "Sci name|Common name" to (re)generate')
    ap.add_argument("--out", type=Path, default=None, help="Illustrations dir (default: profile's illustrations/)")
    ap.add_argument(
        "--refs",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "assets" / "references",
        help="Reference-photo cache (shared with pregen.py)",
    )
    ap.add_argument("--model", default="birefnet-general", help="rembg matting model (default: birefnet-general)")
    ap.add_argument("--margin", type=float, default=0.04, help="crop padding as a fraction of the bird's longer side")
    ap.add_argument("--force", action="store_true", help="regenerate even if <slug>.png already exists")
    ap.add_argument("--limit", type=int, default=0, help="cap species count (for testing)")
    args = ap.parse_args()

    try:
        from PIL import Image
        from rembg import new_session, remove
    except ImportError:
        print("error: needs Pillow + rembg (uv sync / pip install -r requirements.txt)", file=sys.stderr)
        return 2

    out_dir = args.out or art_dir()
    out_dir.mkdir(parents=True, exist_ok=True)
    species = species_from(args)
    session = new_session(args.model)

    done = skipped = failed = 0
    for sci, com in species:
        slug = slugify(sci)
        dest = out_dir / f"{slug}.png"
        if dest.exists() and not args.force:
            skipped += 1
            continue
        ref = ensure_reference(args.refs, slug, sci, com)
        if not ref:
            print(f"  [warn] no Wikipedia photo for {sci}", file=sys.stderr)
            failed += 1
            continue
        try:
            cut = remove(Image.open(ref).convert("RGB"), session=session)  # RGBA, ground -> transparent
            bbox = cut.getchannel("A").getbbox()
            if bbox:
                pad = round(args.margin * max(bbox[2] - bbox[0], bbox[3] - bbox[1]))
                cut = cut.crop(
                    (
                        max(0, bbox[0] - pad),
                        max(0, bbox[1] - pad),
                        min(cut.width, bbox[2] + pad),
                        min(cut.height, bbox[3] + pad),
                    )
                )
            dither_to_spectra6(cut).save(dest)
            done += 1
            print(f"  [flat] {slug}  -> {cut.width}x{cut.height}")
        except Exception as e:  # noqa: BLE001 - one bad photo must not halt the batch
            print(f"  [fail] {sci}: {e}", file=sys.stderr)
            failed += 1

    print(f"\nflat illustrations: {done} generated · {skipped} skipped · {failed} failed  ->  {out_dir}")
    print("next: uv run python pipeline/scripts/build_masks.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
