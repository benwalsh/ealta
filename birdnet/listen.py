#!/usr/bin/env python3
"""Turn real birdsong into detections the collage reads.

A desktop stand-in for what BirdNET-Pi does on the device: run Cornell's
BirdNET over audio and write each identified bird into the `detections` table
(the same schema as birds.db) that the Rails app reads. Two modes:

    # Analyse a recording (a WAV/MP3/FLAC, e.g. from xeno-canto.org)
    python birdnet/listen.py recording path/to/song.wav

    # Listen live on the Mac's microphone until you stop it (Ctrl-C)
    python birdnet/listen.py listen --seconds 15

Location matters: BirdNET weights its predictions by where and when you are, so
the station's coordinates decide which species it will even consider. They are
station config, set via env and never committed:

    BIRD_LAT, BIRD_LON       location for species weighting
    BIRD_MIN_CONF            confidence floor (default 0.25)
    BIRD_DB                  detections DB (default dashboard/storage/development.sqlite3)

Run it through the uv env: `uv run python birdnet/listen.py ...`.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path


def _install_litert_shim():
    """birdnetlib imports `tflite_runtime.interpreter`. Alias it to the
    cross-platform ai-edge-litert runtime (macOS + Pi, Python 3.10-3.14) so the
    same code runs on both without full TensorFlow. Must run before birdnetlib
    is imported. No-ops if litert is absent (falls back to tensorflow.lite)."""
    import types

    try:
        import ai_edge_litert.interpreter as litert
    except ModuleNotFoundError:
        return
    shim = types.ModuleType("tflite_runtime")
    shim.interpreter = litert
    sys.modules.setdefault("tflite_runtime", shim)
    sys.modules.setdefault("tflite_runtime.interpreter", litert)


_install_litert_shim()

REPO = Path(__file__).resolve().parents[1]

SAMPLE_RATE = 48_000  # BirdNET expects 48 kHz mono


def db_path() -> Path:
    return Path(os.environ.get("BIRD_DB", REPO / "dashboard" / "storage" / "development.sqlite3"))


def insert_detections(detections: list[dict], source: str, lat: float, lon: float) -> int:
    """Write BirdNET detections into the detections table. Returns rows added."""
    path = db_path()
    if not path.exists():
        sys.exit(f"detections DB not found at {path} — run the Rails app's db:prepare first")
    now = datetime.now()
    rows = [
        (
            now.strftime("%Y-%m-%d"),
            now.strftime("%H:%M:%S"),
            det["scientific_name"],
            det["common_name"],
            float(det["confidence"]),
            lat,
            lon,
            int(now.isocalendar().week),
            source,
        )
        for det in detections
    ]
    con = sqlite3.connect(path)
    con.execute("PRAGMA busy_timeout=5000")  # wait, don't fail, if the app is mid-read
    try:
        con.executemany(
            "INSERT INTO detections "
            '("Date","Time","Sci_Name","Com_Name","Confidence","Lat","Lon","Week","File_Name") '
            "VALUES (?,?,?,?,?,?,?,?,?)",
            rows,
        )
        con.commit()
    finally:
        con.close()
    return len(rows)


# When we last wrote a liveness tick (monotonic seconds). Throttles the writes so a 15s
# capture loop doesn't insert thousands of rows a day — one a minute is ample resolution.
_last_heartbeat = 0.0
HEARTBEAT_EVERY = 60.0  # seconds between ticks
HEARTBEAT_KEEP = timedelta(days=2)  # ticks older than this are pruned; only the recent window matters


def record_heartbeat(source: str) -> None:
    """Note that the listener captured and analysed a chunk just now, even a quiet one —
    proof the mic -> BirdNET loop is alive. Throttled (see _last_heartbeat) and
    self-pruning so the table stays tiny. A capture error skips this, so a dead mic
    leaves a gap in the ticks rather than a false 'alive'."""
    global _last_heartbeat
    now_mono = time.monotonic()
    if now_mono - _last_heartbeat < HEARTBEAT_EVERY:
        return
    _last_heartbeat = now_mono

    path = db_path()
    if not path.exists():
        return
    now = datetime.now()
    con = sqlite3.connect(path)
    con.execute("PRAGMA busy_timeout=5000")
    try:
        con.execute("INSERT INTO heartbeats (at, source) VALUES (?, ?)", (now.strftime("%Y-%m-%d %H:%M:%S"), source))
        con.execute("DELETE FROM heartbeats WHERE at < ?", ((now - HEARTBEAT_KEEP).strftime("%Y-%m-%d %H:%M:%S"),))
        con.commit()
    finally:
        con.close()


# When we last kicked off a cloud push (monotonic seconds), and a lock so a slow push
# never stacks up behind the next tick.
_last_push = 0.0
PUSH_EVERY = float(os.environ.get("PUSH_EVERY", 300))  # 0 disables the in-loop push
_push_lock = threading.Lock()


def maybe_push() -> None:
    """Every PUSH_EVERY seconds, mirror new detections + heartbeats to the cloud in a
    background thread so `make listen` syncs as it goes — without ever stalling capture.
    A no-op unless CLOUD_INGEST_* are set (push.sync handles that), so it's harmless on a
    stand-alone box."""
    global _last_push
    if PUSH_EVERY <= 0:
        return
    now = time.monotonic()
    if now - _last_push < PUSH_EVERY:
        return
    _last_push = now

    def run() -> None:
        if not _push_lock.acquire(blocking=False):
            return  # a previous push is still going; skip this tick
        try:
            import push  # lazy: push imports back from this module

            push.sync()
        except Exception as err:  # noqa: BLE001 — a mirror hiccup must never touch capture
            print(f"cloud push skipped: {err}", file=sys.stderr)
        finally:
            _push_lock.release()

    threading.Thread(target=run, daemon=True).start()


def analyze_file(analyzer, path: Path, lat: float, lon: float, min_conf: float) -> list[dict]:
    from birdnetlib import Recording

    rec = Recording(analyzer, str(path), lat=lat, lon=lon, date=datetime.now(), min_conf=min_conf)
    rec.analyze()
    return rec.detections


def report(detections: list[dict]) -> None:
    if not detections:
        print("  (nothing identified)")
        return
    seen: dict[str, float] = {}
    for det in detections:
        name = f"{det['common_name']} ({det['scientific_name']})"
        seen[name] = max(seen.get(name, 0), det["confidence"])
    for name, conf in sorted(seen.items(), key=lambda kv: -kv[1]):
        print(f"  {conf:.0%}  {name}")


def cmd_recording(args, analyzer, lat, lon, min_conf):
    path = Path(args.path)
    if not path.exists():
        sys.exit(f"no such file: {path}")
    print(f"analysing {path.name} (location weighting {lat},{lon}, min {min_conf:.0%})...")
    detections = analyze_file(analyzer, path, lat, lon, min_conf)
    report(detections)
    added = insert_detections(detections, path.name, lat, lon)
    print(f"wrote {added} detections -> {db_path().name}")


def resolve_mic():
    """Pick the input device. BIRD_MIC (a name substring, e.g. "USBMIC1")
    selects a specific mic; unset uses the system default."""
    import sounddevice as sd

    want = os.environ.get("BIRD_MIC")
    inputs = [(i, d["name"]) for i, d in enumerate(sd.query_devices()) if d["max_input_channels"] > 0]
    if not want:
        return None, sd.query_devices(kind="input")["name"]
    for i, name in inputs:
        if want.lower() in name.lower():
            return i, name
    sys.exit(f"no input device matching BIRD_MIC={want!r}. Available: " + ", ".join(n for _, n in inputs))


def cmd_listen(args, analyzer, lat, lon, min_conf):
    import sounddevice as sd
    import soundfile as sf

    device, mic_name = resolve_mic()
    print(f"listening on '{mic_name}' in {args.seconds}s chunks (Ctrl-C to stop)...")
    backoff = 1.0
    try:
        while True:
            try:
                audio = sd.rec(int(args.seconds * SAMPLE_RATE), samplerate=SAMPLE_RATE, channels=1, device=device)
                sd.wait()
            except sd.PortAudioError as err:
                # Transient capture glitch (a CoreAudio/ALSA hiccup, a USB mic
                # re-enumerating, device contention). Don't take the whole
                # listener down — warn, drop the half-open stream, back off, and
                # keep going. Backoff caps so an unplugged mic doesn't spin.
                stamp = datetime.now().strftime("%H:%M:%S")
                print(f"[{stamp}] audio capture error ({err}); retrying in {backoff:.0f}s", file=sys.stderr)
                sd.stop(ignore_errors=True)
                time.sleep(backoff)
                backoff = min(backoff * 2, 30.0)
                continue
            backoff = 1.0  # a clean capture resets the backoff
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                sf.write(tmp.name, audio, SAMPLE_RATE)
                detections = analyze_file(analyzer, Path(tmp.name), lat, lon, min_conf)
            os.unlink(tmp.name)
            stamp = datetime.now().strftime("%H:%M:%S")
            if detections:
                print(f"[{stamp}] heard:")
                report(detections)
                insert_detections(detections, "live-mic", lat, lon)
            else:
                print(f"[{stamp}] quiet")
            # Either way the mic was alive and we analysed a chunk — record a liveness
            # tick (throttled) so this window is a true 0, not missing data. Reached only
            # on a clean capture; the PortAudioError branch above `continue`s past it.
            record_heartbeat("live-mic")
            # Mirror detections + ticks to the cloud as we go (throttled, backgrounded),
            # so `make listen` keeps the cloud mirror current with no extra step.
            maybe_push()
    except KeyboardInterrupt:
        print("\nstopped.")


def require_coords() -> tuple[float, float]:
    """The station's coordinates, from the environment. BirdNET weights species by
    location, so a borrowed or wrong location yields confidently wrong birds. The
    engine ships no default: it will not guess where you are."""
    lat, lon = os.environ.get("BIRD_LAT"), os.environ.get("BIRD_LON")
    if not lat or not lon:
        sys.exit("BIRD_LAT and BIRD_LON must be set (see .env.example) — BirdNET weights species by location.")
    return float(lat), float(lon)


def main():
    ap = argparse.ArgumentParser(description="Run BirdNET over audio into the collage's detections table.")
    sub = ap.add_subparsers(dest="mode", required=True)
    rec = sub.add_parser("recording", help="analyse an audio file")
    rec.add_argument("path")
    live = sub.add_parser("listen", help="listen live on the microphone")
    live.add_argument("--seconds", type=int, default=15, help="chunk length (default 15)")
    args = ap.parse_args()

    lat, lon = require_coords()
    min_conf = float(os.environ.get("BIRD_MIN_CONF", 0.25))

    print("loading BirdNET (first run downloads the model)...")
    from birdnetlib.analyzer import Analyzer

    analyzer = Analyzer()

    (cmd_recording if args.mode == "recording" else cmd_listen)(args, analyzer, lat, lon, min_conf)


if __name__ == "__main__":
    main()
