#!/usr/bin/env python3
"""Print the Irish bird list as `Sci|Com` lines, for `pregen.py --labels`.

Scope = species that occur in Ireland: those with a real Irish name in
`model/l18n/labels_ga.json` (BirdWatch Ireland's list — where the `ga` entry
differs from the `en` one), PLUS any species already detected (so a common bird
still missing its Irish name, e.g. Mallard, isn't dropped from a restyle).

    uv run python pipeline/scripts/irish_labels.py            # -> Sci|Com lines
    uv run python pipeline/scripts/irish_labels.py | wc -l    # how many
"""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    en = json.loads((ROOT / "model/l18n/labels_en.json").read_text())
    ga = json.loads((ROOT / "model/l18n/labels_ga.json").read_text())
    keys = [k for k in en if not k.startswith("_")]
    species = {k for k in keys if ga.get(k) and ga.get(k) != en.get(k)}

    db = ROOT / "dashboard/storage/development.sqlite3"
    if db.exists():
        con = sqlite3.connect(str(db))
        try:
            for (sci,) in con.execute("SELECT DISTINCT Sci_Name FROM detections"):
                if sci in en:
                    species.add(sci)
        except sqlite3.Error:
            pass
        con.close()

    for key in sorted(species):
        print(f"{key}|{en[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
