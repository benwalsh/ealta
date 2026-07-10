#!/usr/bin/env python3
"""Lazy Pi -> cloud push (the cold path).

Reads new rows from the shared SQLite and POSTs them to the cloud ingest endpoints,
so the cloud mirror reflects what the wall has heard AND whether the mic is alive. The
Pi stays the source of truth; this is a one-way, best-effort, eventually-consistent copy.

  * Offline-tolerant: on any failure the high-water cursor is NOT advanced, so the
    next run re-sends and catches up. Nothing is lost, the listener never blocks.
  * Idempotent: each row carries a dedupe_key (SHA-256 of the columns the cloud's
    unique index uses), so re-POSTing a batch never double-inserts.

Two streams, each with its own cursor: detections (what was heard) and heartbeats (that
the listener was alive, even when quiet — so the cloud can tell a true zero from missing
data). Both no-op unless CLOUD_INGEST_URL and CLOUD_INGEST_TOKEN are set.

Run standalone (`python birdnet/push.py`, or ealta-push.timer), or called every few
minutes from the live listener itself (see listen.py's maybe_push) so `make listen`
mirrors as it goes.
"""

import hashlib
import json
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.request
from pathlib import Path

from listen import db_path  # reuse the shared-DB locator

BATCH = 500
ROOT = Path(__file__).resolve().parent.parent
# High-water marks: the id of the last row pushed per stream. Repo-root, gitignored —
# device sync state, deliberately NOT in the shared DB.
DETECTION_CURSOR = ROOT / ".sync_cursor"
HEARTBEAT_CURSOR = ROOT / ".sync_cursor_heartbeats"

# Columns sent to the cloud (everything the listener writes). id is the cursor, not part
# of the payload — the cloud assigns its own primary key.
COLUMNS = ["Date", "Time", "Sci_Name", "Com_Name", "Confidence", "Lat", "Lon", "Week", "File_Name"]
# The subset hashed into each dedupe_key — must match the cloud's unique index.
KEY_COLUMNS = ["Date", "Time", "Sci_Name", "Confidence", "File_Name"]
HEARTBEAT_COLUMNS = ["at", "source"]


def dedupe_key(row: dict, columns: list[str]) -> str:
    raw = "|".join(str(row[c]) for c in columns)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def read_cursor(path: Path) -> int:
    try:
        return int(path.read_text().strip())
    except (FileNotFoundError, ValueError):
        return 0


def write_cursor(path: Path, last_id: int) -> None:
    path.write_text(str(last_id))


def new_rows(con: sqlite3.Connection, table: str, columns: list[str], since_id: int) -> list[dict]:
    cols = ",".join(f'"{c}"' for c in columns)
    cur = con.execute(
        f"SELECT id,{cols} FROM {table} WHERE id > ? ORDER BY id LIMIT ?",
        (since_id, BATCH),
    )
    return [dict(r) for r in cur.fetchall()]


def post(url: str, token: str, key: str, rows: list[dict]) -> bool:
    body = json.dumps({key: rows}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status == 200
    except urllib.error.URLError as err:
        print(f"push to {url} failed, will retry next run: {err}", file=sys.stderr)
        return False


def heartbeats_url(detections_url: str) -> str:
    """The heartbeats endpoint sits beside detections (…/ingest/detections → …/heartbeats)."""
    return re.sub(r"/detections/?$", "/heartbeats", detections_url.rstrip("/"))


def push_stream(con, *, table, columns, key_columns, cursor, url, token, payload_key, dry_run) -> int:
    """Push one stream (detections or heartbeats) in id order, advancing its cursor only
    on a clean 200 so an outage just replays from where it stopped."""
    since = read_cursor(cursor)
    pushed = 0
    while True:
        rows = new_rows(con, table, columns, since)
        if not rows:
            break
        last_id = rows[-1]["id"]
        payload = [{**{c: r[c] for c in columns}, "dedupe_key": dedupe_key(r, key_columns)} for r in rows]

        if dry_run:
            print(json.dumps(payload[:2], indent=2, ensure_ascii=False))
            print(f"... {len(payload)} {payload_key} since id {since} (dry run — not sent)")
            break

        if not post(url, token, payload_key, payload):
            break  # leave the cursor; next run retries from here
        since = last_id
        write_cursor(cursor, since)
        pushed += len(rows)
        if len(rows) < BATCH:
            break
    return pushed


def sync(dry_run: bool = False) -> None:
    """Mirror new detections + heartbeats to the cloud. No-ops (quietly, so it's safe to
    call from the listen loop) unless CLOUD_INGEST_URL / CLOUD_INGEST_TOKEN are set."""
    url = os.environ.get("CLOUD_INGEST_URL")
    token = os.environ.get("CLOUD_INGEST_TOKEN")
    if not url or not token:
        if dry_run:
            print("CLOUD_INGEST_URL / CLOUD_INGEST_TOKEN unset — nothing to push")
        return

    con = sqlite3.connect(db_path())
    con.row_factory = sqlite3.Row
    try:
        detections = push_stream(
            con,
            table="detections",
            columns=COLUMNS,
            key_columns=KEY_COLUMNS,
            cursor=DETECTION_CURSOR,
            url=url,
            token=token,
            payload_key="detections",
            dry_run=dry_run,
        )
        ticks = push_stream(
            con,
            table="heartbeats",
            columns=HEARTBEAT_COLUMNS,
            key_columns=HEARTBEAT_COLUMNS,
            cursor=HEARTBEAT_CURSOR,
            url=heartbeats_url(url),
            token=token,
            payload_key="heartbeats",
            dry_run=dry_run,
        )
    finally:
        con.close()
    if not dry_run:
        print(f"pushed {detections} detections, {ticks} heartbeats")


def main() -> None:
    sync(dry_run="--dry-run" in sys.argv)


if __name__ == "__main__":
    main()
