"""Where a station's bird art lives.

The engine ships no illustrations. Art is the output of a station's own style
(its profile's image/prompt.template.md), so it belongs to that profile — the same
way its lore, calendar and brand mark do. Point STATION_PROFILE at your profile and
the pipeline reads and writes there.

With STATION_PROFILE unset, everything falls back to a scratch directory inside the
repo (gitignored), so you can experiment before you have a profile of your own.

    from art import art_dir, masks_json
"""

import os
from pathlib import Path

PIPELINE = Path(__file__).resolve().parents[1]
SCRATCH = PIPELINE / "assets" / "illustrations"


def art_dir() -> Path:
    """The active station's illustrations directory."""
    profile = os.environ.get("STATION_PROFILE")
    return Path(profile).expanduser() / "illustrations" if profile else SCRATCH


def masks_json() -> Path:
    """masks.json sits with the art it describes."""
    return art_dir() / "masks.json"
