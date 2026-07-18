#!/usr/bin/env bash
#
# Provision the bird device on a fresh Raspberry Pi OS Lite (Bookworm,
# arm64). Idempotent — safe to re-run. Goal: flash → SSH in → run this → done.
#
# The ARM Debian validation container runs this with EALTA_CONTAINER=1, which
# skips the Pi-only bits (SPI, hardware groups, systemd, the inky driver,
# Tailscale, Wi-Fi) and exercises only the software path — packages, toolchains,
# Rails native-gem builds, the database, and the doctor seam check. See
# deploy/Dockerfile.armcheck.
#
set -euo pipefail

REPO="${EALTA_REPO:-$HOME/ealta}"
IN_CONTAINER="${EALTA_CONTAINER:-0}"
SUDO="$([ "$(id -u)" -eq 0 ] && echo '' || echo sudo)"

say() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }

# ----------------------------------------------------------------- packages --
say "system packages (apt)"
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends \
  git build-essential ca-certificates curl xz-utils unzip \
  libsndfile1 portaudio19-dev \
  fonts-ebgaramond chromium \
  libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libsqlite3-dev sqlite3

# -------------------------------------------------- Pi hardware interfaces ---
if [ "$IN_CONTAINER" != "1" ]; then
  say "Pi interfaces: SPI/I2C + groups (Inky HAT, mic)"
  $SUDO raspi-config nonint do_spi 0 || echo "  (raspi-config SPI: skipped)"
  $SUDO raspi-config nonint do_i2c 0 || echo "  (raspi-config I2C: skipped)"
  $SUDO usermod -aG audio,spi,i2c,gpio "$USER" || true
  echo "  NB: re-login or reboot for the new groups to take effect."
fi

# --------------------------------------------------------------- toolchains --
say "toolchains (uv, bun, mise + Ruby)"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.bun/bin:$PATH"
command -v uv  >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
command -v bun >/dev/null || curl -fsSL https://bun.sh/install | bash
# MISE_INSTALL_MUSL=1 forces mise's static musl build — recent mise gnu builds
# require glibc 2.39, but Raspberry Pi OS / Debian Bookworm ship glibc 2.36. The
# musl binary has no glibc dependency, so it runs anywhere (and still compiles
# Ruby against the system toolchain fine).
command -v mise >/dev/null || curl -fsSL https://mise.run | MISE_INSTALL_MUSL=1 sh
# Ruby from .ruby-version (mise compiles it via ruby-build — slow the first time
# on ARM; subsequent runs are cached).
( cd "$REPO/dashboard" && mise use "ruby@$(cat .ruby-version)" )

# ---------------------------------------------------------- app: deps + db --
if [ ! -f "$REPO/.env" ]; then
  echo "error: $REPO/.env not found — copy .env.example and fill BIRD_DB," \
       "SECRET_KEY_BASE, coords + mic before provisioning." >&2
  exit 1
fi
set -a; . "$REPO/.env"; set +a
export RAILS_ENV=production LANG=C.UTF-8 LC_ALL=C.UTF-8

say "python deps (uv sync)"
( cd "$REPO" && uv sync )

say "ruby/js deps + production assets"
cd "$REPO/dashboard"
# The `cloud` group (trilogy/MySQL) is for the public cloud mirror only — the Pi
# runs on SQLite and never needs it, so don't compile it here.
bundle config set --local without cloud
bundle install
bun install
# Vite builds both bundles (the Stimulus/Turbo `application` entry + the React
# `app` SPA) into public/vite. Run it explicitly so the ARM container validates
# the build too (assets:precompile below, which also triggers it, is Pi-only).
bin/vite build
# Asset precompile copies the bird PNGs under /birds + digests the Propshaft CSS;
# the validation container doesn't ship the PNGs, and they're not the ARM risk,
# so skip it there.
[ "$IN_CONTAINER" = "1" ] || bin/rails assets:precompile

say "database (creates the shared SQLite + tables, sets WAL)"
bin/rails db:prepare

say "seam check (ealta:doctor)"
bin/rails ealta:doctor

if [ "$IN_CONTAINER" = "1" ]; then
  say "container validation OK — software path is good"
  exit 0
fi

# ----------------------------------------------------- Pi-only: panel + svc --
say "Inky panel driver (SPI/GPIO) + headless Chromium"
( cd "$REPO" && uv pip install inky )
( cd "$REPO" && uv run playwright install --with-deps chromium ) ||
  echo "  (playwright install failed — point the shooter at apt 'chromium' if needed)"

say "systemd services"
cd "$REPO"
sed -i "s/\bpi\b/$USER/g; s#/home/pi#$HOME#g" deploy/ealta-*.service
$SUDO cp deploy/ealta-*.service deploy/ealta-*.timer /etc/systemd/system/
$SUDO systemctl daemon-reload
# ealta-restore is a boot-time oneshot (recovers the DB from the offsite replica before
# the web's db:prepare), ordered ahead of the web — enable it so a power cut or SD-card
# death comes back with its history, not an empty database.
$SUDO systemctl enable --now ealta-restore ealta-listener ealta-web ealta-frame.timer

# Let the web app restart JUST the listener unit (the admin "restart listener" button) without a
# password — a single, tightly-scoped sudoers rule, nothing else. validated with visudo -cf.
if [ "$IN_CONTAINER" != "1" ]; then
  RULE="$USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart ealta-listener.service"
  echo "$RULE" | $SUDO tee /etc/sudoers.d/ealta-listener >/dev/null
  $SUDO chmod 0440 /etc/sudoers.d/ealta-listener
  $SUDO visudo -cf /etc/sudoers.d/ealta-listener >/dev/null || \
    { echo "  (sudoers rule failed validation — removing)"; $SUDO rm -f /etc/sudoers.d/ealta-listener; }
fi

# Cloud mirror push (Pi -> the cloud mirror) — only if the ingest keys are set.
if [ -n "${CLOUD_INGEST_URL:-}" ]; then
  say "cloud mirror push (every 15 min)"
  $SUDO systemctl enable --now ealta-push.timer
else
  echo "  (CLOUD_INGEST_URL unset — skipping cloud push; set CLOUD_INGEST_URL/TOKEN in .env to enable)"
fi

# Offsite backup (Litestream -> S3/B2) — only if the LITESTREAM_* keys are set.
if [ -n "${LITESTREAM_BUCKET:-}" ]; then
  say "Litestream (offsite DB backup to S3/B2)"
  if ! command -v litestream >/dev/null; then
    LS_VER=0.3.13
    curl -fsSL "https://github.com/benbjohnson/litestream/releases/download/v${LS_VER}/litestream-v${LS_VER}-linux-arm64.deb" -o /tmp/litestream.deb
    $SUDO dpkg -i /tmp/litestream.deb
  fi
  $SUDO systemctl enable --now ealta-litestream
else
  echo "  (LITESTREAM_BUCKET unset — skipping offsite backup; set the LITESTREAM_* keys in .env to enable)"
fi

# ----------------------------------------------- remote access + Wi-Fi -------
say "Tailscale (outbound-only remote SSH)"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | $SUDO sh
if [ -n "${TS_AUTHKEY:-}" ]; then
  $SUDO tailscale up --ssh --authkey "$TS_AUTHKEY"
else
  echo "  set TS_AUTHKEY in .env then: sudo tailscale up --ssh"
fi

# Pre-load both Wi-Fi networks so it associates wherever it boots: the one you provision it
# on, and the one it will live on. Named by ROLE, never by place — this is the engine, and it
# describes no particular house. Creds from .env (SETUP_WIFI_SSID/_PSK, STATION_WIFI_SSID/_PSK
# — gitignored, both optional).
say "Wi-Fi networks (NetworkManager)"
add_wifi() { # name ssid psk
  [ -n "$2" ] || return 0
  $SUDO nmcli connection show "$1" >/dev/null 2>&1 && return 0
  $SUDO nmcli connection add type wifi con-name "$1" ssid "$2" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$3" connection.autoconnect yes
}
add_wifi setup   "${SETUP_WIFI_SSID:-}"   "${SETUP_WIFI_PSK:-}"
add_wifi station "${STATION_WIFI_SSID:-}" "${STATION_WIFI_PSK:-}"

say "provisioning complete — http://$(hostname).local:4030/"
