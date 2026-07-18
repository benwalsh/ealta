# Deploying to the Raspberry Pi

The wall device: a Pi 4 driving a Pimoroni Inky Impression 7.3" (Spectra 6,
800×480), with the USB bird mic. Three services run on boot:

| Service | What it does |
|---|---|
| `ealta-listener` | reads the USB mic → BirdNET → writes `birds.db` |
| `ealta-web` | the Rails app on `:4030` (serves `/station` for the wall, plus the web UI) |
| `ealta-frame` (timer) | screenshots `/station`, advances the slow gallery on the Inky |
| `ealta-almanac` (timer) | every 30 min, refreshes `storage/almanac.json` (weather + tide + coords) from Open-Meteo — no API key |
| `ealta-push` (timer) | every 15 min, pushes new detections to the cloud mirror — only if `CLOUD_INGEST_URL`/`TOKEN` are set |

The whole stack runs **bare-metal** (no Docker — the mic and the SPI/GPIO panel
make container hardware passthrough more trouble than it's worth). Reproducibility
comes from the lockfiles: `uv.lock`, `Gemfile.lock`, `.python-version`,
`.ruby-version`.

## 1. OS + interfaces

Flash Raspberry Pi OS Lite (64-bit). Then on the Pi:

```bash
sudo raspi-config        # Interface Options → enable SPI and I2C (the Inky HAT)
sudo apt update && sudo apt install -y git build-essential libsndfile1 \
     portaudio19-dev fonts-ebgaramond chromium-browser \
     libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libsqlite3-dev
     # ^ the last line: ruby-build needs these to compile Ruby 4.0.5, + sqlite3 gem
sudo usermod -aG audio,spi,i2c,gpio "$USER"   # mic + panel access; re-login after
```

`fonts-ebgaramond` matters: the panel's SVG falls back to **EB Garamond** for the
serif when Baskerville (a macOS font) is absent, so the type renders the same on
the glass as on the Mac.

## 2. Toolchains (the same managers as the Mac)

```bash
curl https://mise.run | sh            # or rbenv, for Ruby 4.0.5 from .ruby-version
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv (installs its own Python 3.12)
curl -fsSL https://bun.sh/install | bash          # bun (JS)
```

## 3. The app

```bash
git clone <this-repo> ~/ealta && cd ~/ealta
cp .env.example .env    # then edit (see below)
make setup              # uv sync, bundle, bun install, bin/vite build, db:prepare

# Production assets — needs SECRET_KEY_BASE set in .env first (boots prod env).
# assets:precompile runs the Vite build (the `/` React SPA + the /kiosk,/station
# Stimulus bundle → public/vite) AND digests the Propshaft CSS + bird PNGs into
# public/assets & public/birds:
cd dashboard && RAILS_ENV=production bin/rails assets:precompile && cd ..

# Pi-only extras (kept out of the cross-platform lock):
uv pip install inky                       # the Spectra-6 panel driver (SPI/GPIO)
uv run playwright install --with-deps chromium   # headless browser for the shooter
```

`.env` on the device — the station's own coordinates, plus the two
production-only keys:

```
BIRD_LAT=<station latitude>
BIRD_LON=<station longitude>
BIRD_MIN_CONF=0.6
BIRD_MIC=<usb mic name, see: uv run python -c "import sounddevice;print(sounddevice.query_devices())">
BIRD_DB=/home/pi/ealta/dashboard/storage/production.sqlite3   # ABSOLUTE; shared by listener + Rails
SECRET_KEY_BASE=<cd dashboard && RAILS_ENV=production bin/rails secret>
```

There is **one shared SQLite** (`BIRD_DB`): the listener writes the `detections`
table, the web app reads them and owns `species_infos`. The web service's
`db:prepare` creates the file and its tables (in WAL mode) on first boot; the
listener is ordered after it so the DB exists before it writes. No second DB, no
read-only split — `BIRD_DB` is the single source of truth both runtimes point at.

**Confirm the seams before wiring services** (creates the DB, checks the
datastore/locale end to end — should print `all seams good ✓`):

```bash
cd dashboard && RAILS_ENV=production bin/rails db:prepare && RAILS_ENV=production bin/rails ealta:doctor && cd ..
```

## 4. Services

```bash
sed -i "s/\bpi\b/$USER/g; s#/home/pi#$HOME#g" deploy/ealta-*.service   # fix user/paths
sudo cp deploy/ealta-*.service deploy/ealta-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ealta-listener ealta-web ealta-frame.timer ealta-almanac.timer
journalctl -u ealta-frame -f      # watch panel pushes
```

## 5. First light

- `uv run python shooter/shoot.py --preview /tmp/f.png` then `eog /tmp/f.png` — check the `/station` look before pushing to glass.
- Drop the preview and run `shooter/shoot.py` for real; tune `--rotate` (how the frame hangs) and `--saturation` on the actual panel — colours and dithering differ from the preview, so do a final pass on the glass.

## AWS credentials (a static key, not SSO)

For dev you can `aws sso login` on the Pi, but the wall device runs unattended for
months and an SSO session expires — so give it a **static, least-privilege key**
instead. `infrastructure/device.tf` provisions a dedicated IAM user scoped to exactly
what the device does on its own (offsite backup, Bedrock summary, illustration read).
After `tofu apply`, read the key and put it in `.env`:

```bash
cd infrastructure
tofu output device_backup_bucket           # -> LITESTREAM_BUCKET
tofu output -raw device_access_key_id       # -> LITESTREAM_ACCESS_KEY_ID + AWS_ACCESS_KEY_ID
tofu output -raw device_secret_access_key   # -> LITESTREAM_SECRET_ACCESS_KEY + AWS_SECRET_ACCESS_KEY
```

The same pair covers Litestream (S3), the daily-summary Bedrock call, and
`bin/sync-illustrations pull`. Stations that back up to Backblaze B2 or another non-AWS
store skip `device.tf` and use that provider's own keys for `LITESTREAM_*`.

## Offsite backup (Litestream → S3/B2)

The station Pi is unattended on flaky broadband, so the detection history is backed
up offsite. WAL is on (`database.yml`); `deploy/ealta-litestream.service` +
`deploy/litestream.yml` replicate the DB to object storage. `provision.sh` installs
Litestream and enables the service automatically **once the `LITESTREAM_*` keys are
set in `.env`** (bucket, region, access key/secret; `LITESTREAM_ENDPOINT` for B2).

### Crash / power-outage recovery (automatic)

The box is built to come back on its own from a crash, power cut, or SD-card death:

- **Services self-heal and restart on boot** — `ealta-web`, `ealta-listener` and
  `ealta-litestream` are `Restart=always`, `WantedBy=multi-user.target`, and set
  `StartLimitIntervalSec=0` so they never permanently give up; the timers are
  `Persistent=true` so a run missed during an outage fires on the next boot.
- **The DB survives a power cut** — WAL + `synchronous=NORMAL` (`database.yml`) make
  SQLite commits atomic, so a cut mid-write can lose the last transaction but not corrupt
  the file.
- **Restore-on-boot** — `ealta-restore.service` runs `deploy/restore-if-needed.sh`
  **before** the web app's `db:prepare`: if the DB is missing or fails
  `PRAGMA integrity_check` it pulls it back from the Litestream offsite replica (a corrupt
  file is moved aside to `birds.db.corrupt-<ts>` first). Without it, `db:prepare` would
  create an *empty* DB and silently lose the history. It no-ops when the DB is healthy or
  Litestream is unset, and always exits 0 so a hiccup degrades rather than bricks the box.

Manual restore, if ever needed:

```bash
litestream restore -config deploy/litestream.yml "$BIRD_DB"
```

## Still to wire (deferred)

- **Headless Chromium on ARM** — if `playwright install` is unhappy on the Pi, point
  the shooter at the apt `chromium` instead.
