#!/usr/bin/env python3
"""Screenshot the /station wall programme and push it to the e-ink panel.

The bridge from the Rails app to the glass. The app renders the /station view at
the station's OWN screen size (station.yml `screen:` — name, width, height); this
screenshots that screen with a headless browser and pushes the pixels to the
panel. With no `screen:` configured the station has no glass, and this exits
quietly doing nothing. The reference driver is Pimoroni's Inky (Spectra 6); any
panel with a Python driver can slot into push_inky's place.

    # On the Mac (no panel): write the Spectra-6 dither to inspect the look
    uv run python shooter/shoot.py --preview frame.png

    # On the Pi: push to the panel (only when the birds changed)
    uv run python shooter/shoot.py

The Inky library is Python-only and Pi-only (SPI/GPIO), so it's lazy-imported —
this script loads and previews fine on a machine without the hardware. To save
the e-ink panel from needless refreshes, it skips the push when the screenshot
is identical to the last one (override with --force).
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import sys
from pathlib import Path

from PIL import Image, ImageEnhance

# Approximate Spectra-6 inks, for the desktop --preview dither only. On the Pi
# the Inky library maps to the panel's real palette.
SPECTRA6 = [(236, 234, 223), (26, 26, 28), (165, 60, 56), (198, 176, 74), (49, 71, 130), (58, 110, 72)]

DEFAULT_URL = "http://localhost:3000/station"  # the Makefile passes the station-resolved port
DEFAULT_SELECTOR = ".station"
DEFAULT_STATE = "~/.birdframe/state"


def screen_config() -> dict | None:
    """The station's screen (name/width/height) from $STATION_PROFILE/station.yml, or None.

    None means the station has no physical panel: the shooter (and the /station page it
    would capture) simply don't apply. Falls back to the shipped example profile the same
    way the Rails side does."""
    import yaml

    root = Path(__file__).resolve().parents[1]
    for profile in [os.environ.get("STATION_PROFILE"), root / "stations" / "example"]:
        if not profile:
            continue
        f = Path(profile) / "station.yml"
        if not f.is_file():
            continue
        cfg = (yaml.safe_load(f.read_text()) or {}).get("screen")
        if isinstance(cfg, dict) and int(cfg.get("width") or 0) > 0 and int(cfg.get("height") or 0) > 0:
            return {"name": cfg.get("name") or "e-ink screen",
                    "width": int(cfg["width"]), "height": int(cfg["height"])}
        if cfg is not None:
            return None
    return None


def screenshot(url: str, selector: str, width: int, height: int, timeout_ms: int = 30_000) -> bytes:
    """Render the station page and return PNG bytes of the selected panel area."""
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height})
        try:
            page.goto(url, wait_until="networkidle", timeout=timeout_ms)
            element = page.wait_for_selector(selector, timeout=timeout_ms)
            png = element.screenshot()
        finally:
            browser.close()
    return png


def dither_spectra6(img: Image.Image, saturation: float = 0.6) -> Image.Image:
    img = img.convert("RGB")
    # The panel muts colour by `saturation` on hardware (Inky.set_image), which tames
    # the coloured-ink speckle a naive quantise sprays into near-neutral areas (dark
    # birds especially). Mirror it here so the desktop preview isn't more garish than
    # the real thing.
    if saturation < 1.0:
        img = ImageEnhance.Color(img).enhance(saturation)
    pal = Image.new("P", (1, 1))
    flat = [c for ink in SPECTRA6 for c in ink]
    flat += list(SPECTRA6[0]) * ((768 - len(flat)) // 3)
    pal.putpalette(flat[:768])
    return img.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB")


def push_inky(img: Image.Image, saturation: float, rotate: int) -> None:
    """Push to the panel. Lazy import so the module loads without the hardware."""
    import inspect

    from inky.auto import auto

    panel = auto()
    if rotate:
        img = img.rotate(rotate, expand=True)
    if img.size != (panel.width, panel.height):
        img = img.resize((panel.width, panel.height), Image.LANCZOS)
    kwargs = {"saturation": saturation} if "saturation" in inspect.signature(panel.set_image).parameters else {}
    panel.set_image(img, **kwargs)
    panel.show()


def read_state(path: Path) -> str | None:
    try:
        return path.read_text().strip()
    except OSError:
        return None


def write_state(path: Path, digest: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(digest)


def main() -> int:
    ap = argparse.ArgumentParser(description="Screenshot the station view and push it to the Inky.")
    ap.add_argument("--url", default=DEFAULT_URL, help=f"station page (default {DEFAULT_URL})")
    ap.add_argument("--selector", default=DEFAULT_SELECTOR, help=f"element to screenshot (default {DEFAULT_SELECTOR})")
    ap.add_argument("--preview", metavar="PATH", help="write the Spectra-6 dither here instead of pushing")
    ap.add_argument("--rotate", type=int, default=0, choices=[0, 90, 180, 270], help="panel rotation")
    ap.add_argument("--saturation", type=float, default=0.6, help="Inky colour saturation 0-1")
    ap.add_argument("--force", action="store_true", help="push even if the panel is unchanged")
    ap.add_argument("--state", default=DEFAULT_STATE, help="file holding the last-pushed signature")
    args = ap.parse_args()

    screen = screen_config()
    if screen is None:
        print("no screen: configured in station.yml — nothing to shoot")
        return 0
    print(f"shooting for {screen['name']} ({screen['width']}x{screen['height']})")

    try:
        png = screenshot(args.url, args.selector, screen["width"], screen["height"])
    except Exception as exc:  # noqa: BLE001 — surface any browser/network failure plainly
        print(f"screenshot failed ({args.url}): {exc}", file=sys.stderr)
        return 1
    img = Image.open(io.BytesIO(png)).convert("RGB")

    if args.preview:
        dither_spectra6(img, args.saturation).save(args.preview)
        print(f"wrote preview {args.preview} (saturation {args.saturation})")
        return 0

    digest = hashlib.sha256(png).hexdigest()[:16]
    state = Path(os.path.expanduser(args.state))
    if not args.force and digest == read_state(state):
        print("unchanged; skip panel refresh")
        return 0

    try:
        push_inky(img, args.saturation, args.rotate)
    except Exception as exc:  # noqa: BLE001
        print(f"panel push failed: {exc}", file=sys.stderr)
        return 1
    write_state(state, digest)
    print("panel updated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
