#!/usr/bin/env bash
# Boot-time recovery guard for the shared bird DB. If it's missing or corrupt — an SD-card
# death, or a power cut mid-write — restore it from the Litestream offsite replica BEFORE
# the web app runs db:prepare, which would otherwise create an EMPTY DB and silently lose
# the detection history. No-ops when the DB is healthy or Litestream isn't configured, and
# always exits 0: a recovery hiccup must degrade (come up, keep listening) not brick the box.
set -uo pipefail

DB="${BIRD_DB:?BIRD_DB must be set (it lives in .env)}"
CONF="$(cd "$(dirname "$0")" && pwd)/litestream.yml"

restore() {
  if [ -z "${LITESTREAM_BUCKET:-}" ]; then
    echo "[restore] Litestream not configured — db:prepare will create a fresh DB" >&2
    return 0
  fi
  if ! command -v litestream >/dev/null; then
    echo "[restore] litestream binary missing — cannot restore" >&2
    return 0
  fi
  echo "[restore] restoring $DB from the offsite replica…" >&2
  litestream restore -if-db-not-exists -config "$CONF" "$DB" \
    || echo "[restore] restore failed (no replica yet?) — continuing with a fresh DB" >&2
}

mkdir -p "$(dirname "$DB")"

if [ ! -f "$DB" ]; then
  echo "[restore] DB missing at $DB" >&2
  restore
elif command -v sqlite3 >/dev/null && ! sqlite3 "$DB" 'PRAGMA integrity_check;' 2>/dev/null | grep -qx ok; then
  echo "[restore] DB failed integrity_check — moving it aside and restoring" >&2
  ts="$(date +%Y%m%d-%H%M%S)"
  mv -f "$DB" "$DB.corrupt-$ts" 2>/dev/null || true
  rm -f "$DB-wal" "$DB-shm" 2>/dev/null || true
  restore
else
  echo "[restore] DB healthy" >&2
fi

exit 0
