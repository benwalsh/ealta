# CLAUDE.md — Ealta

Operating notes for agents working on the engine. What Ealta *is*, the quickstart, and
how to make your own station are in [`README.md`](README.md); this file carries the
architecture, the invariants, and the footguns.

## This repo is public and generic

Ealta is the open-source engine. **A station is defined entirely by its profile.** Keep
personal or site-identifying material out of this repo — coordinates, names, addresses,
hardware bills of materials, install notes, credentials. Those belong in a private station
overlay (which typically wraps this repo as a git submodule and supplies only its profile).

## Two runtimes, one file

- **Python** (`birdnet/`) — audio capture → BirdNET (TFLite) identification. Writes the
  `detections` table. Python because the BirdNET/Inky ecosystem is Python; don't fight it.
- **Ruby/Rails + React** (`dashboard/`) — reads `detections`, owns `species_infos`, serves
  the SPA, the JSON API, and the e-ink panel view.

**The datastore is the contract between them**: a single SQLite file in WAL mode, so both
runtimes can touch it concurrently with no database server. That shared file is why the
device is SQLite. Keep schema changes **additive** so neither runtime surprises the other,
and keep encoding correct on both sides so Irish fadas survive.

## Layout

| dir | what |
|---|---|
| `birdnet/` | the listener: capture → BirdNET → detections + heartbeats |
| `dashboard/` | Rails + React ("Éist") — SPA, `/api/*`, the panel view |
| `pipeline/` | illustration / cutout / mask generation (Gemini + Pillow) |
| `model/` | BirdNET model, label sets (`l18n/labels_*.json`), conservation data |
| `shooter/` | screenshots the panel for the Inky |
| `deploy/` | `provision.sh`, systemd units, Litestream, the boot restore guard |
| `stations/` | station profiles; `stations/example` is the neutral fallback |

The image pipeline is a **build-time step on a desktop**. The device only ever loads
finished rendered assets — it never generates art.

## Station profiles

`STATION_PROFILE` (an **absolute** path) selects the profile. Anything it doesn't override
falls back to `stations/example` — the nameless, English-only station. A profile supplies
place, language, curated content (lore, calendar), a source allowlist, and the illustration
prompt. Scaffold one with `make new-station NAME=yourplace`.

If a station's Irish names, curated lore, or almanac vanish, suspect `STATION_PROFILE` is
unset and the app has silently fallen back to `example`.

## Running it

`.env` is **shell-sourced** by the Makefile (`set -a; source .env; set +a`) — it is shell
syntax, not a config format. **No spaces around `=`**: `FOO= /path` sets `FOO` empty and
then tries to *execute* `/path`. Paths must be absolute.

```bash
make setup     # deps (Python, Ruby, JS) + database
make serve     # Rails only — see the vite gotcha
make listen    # mic → detections → local DB → cloud mirror
make push      # backfill the cloud mirror
make doctor    # Python↔Rails↔datastore seams + Irish locale
make armcheck  # validate the macOS→Pi gap in an arm64 Debian container
```

**Vite gotcha.** `make serve` starts **Rails only** — it does *not* start `bin/vite dev`.
In development the SPA is served from an autobuilt bundle in `public/vite-dev`, while
`make build` writes a **production** bundle to `public/vite` that development never reads.
For frontend work run it the intended way:

```bash
cd dashboard && bin/dev     # Procfile.dev: rails + vite dev together
```

## Environments and databases

| env | runs on | adapter |
|---|---|---|
| `development`, `production` (**the device**) | SQLite, one WAL file | `sqlite3` |
| `cloud` (optional public mirror) | MySQL on RDS | `trilogy` (pure Ruby) |

**Every migration must be legal on both engines.** The trap: a **literal default on a
JSON/TEXT/BLOB column** is accepted by SQLite and rejected by MySQL with error 1101. It
will pass every local test and crash-loop the cloud on boot, because migrations run at
startup. Use an expression default:

```ruby
t.json :blocks, null: false, default: -> { "(JSON_ARRAY())" }   # not default: []
```

Local development **cannot** catch this class of bug. Exercising migrations against MySQL
in CI is the only real guard.

**Almanac gate.** `Almanac` returns `nil` unless `BIRD_LAT` and `BIRD_LON` are in the
environment — which removes **weather, tides, *and* the sparkline** together, since they
all render in the almanac row. Coordinates live in the environment, never in a profile.

## The cloud mirror is optional

The `Dockerfile` builds the cloud image (`RAILS_ENV=cloud`, MySQL via `trilogy`). **The
device never uses it** — a Pi runs bare-metal from the repo via `deploy/`. Detections reach
the mirror through the `/ingest` upsert push (`CLOUD_INGEST_URL` + `CLOUD_INGEST_TOKEN`);
the endpoint is **404 anywhere the token is unset**, which is what switches it on. Data
never crosses engines directly — the push is an upsert, not a database copy.

## Frontend

The React SPA lives in `dashboard/app/javascript/ealta`. It is seeded from a
**server-rendered bootstrap blob** (`@bootstrap`), so signed-in state arrives with the page
load rather than via a fetch. If the header still says "Sign in" after a successful OAuth
round-trip, `session[:user_id]` didn't survive the callback.

**There is no React error boundary.** A single component throw blanks the *entire* SPA, not
just the offending tab — budget for that when something "renders nothing."

Everything is bilingual, Irish first: user-facing strings come in `en`/`ga` pairs via
`t('English', 'Gaeilge')`.

## Design precepts (the keel)

Two precepts govern the whole product. They erode one reasonable-seeming feature at a time,
so they are written down. Everything in the dashboard supports one of the two.

**1. The e-ink voice, everywhere.** The device is a six-colour Spectra e-ink panel showing
dithered bird illustrations on a calm, paper-like surface. The website is that same
object's voice — it inherits the e-ink aesthetic even on screens that aren't e-ink.

- Restrained palette, generous quiet, ink-on-paper stillness. No glow, no gradients, no
  gratuitous motion, no glossy chrome. Whitespace is a feature.
- **Line icons, never emoji** — engraved marks, set in a muted weight so they sit *behind*
  the content like a printer's mark.
- Irish names in the serif voice-italic: a quiet typographic texture that carries the
  bilingual character without shouting.
- **The one deliberate exception** is the 24-hour sparkline — a smooth, continuous, living
  line, precisely what e-ink cannot render. That tension (mostly paper, one live gesture)
  *is* the aesthetic. It is the only moving element; adding more breaks the spell.

**2. Rigorous factuality about birds.** Anything the system says about a bird must be true
and supported. A confidently wrong bird fact is the failure that matters.

- **Ruby computes, the LLM narrates.** `DailyFacts` computes every count, ranking, "first",
  rarity and importance score; the model only turns an already-correct facts object into
  prose; the stats page renders the same object and never re-derives. One source of truth.
  That seam is what keeps warmth from ever costing accuracy.
- State only what the data supports; every clause traces to a fact. **No invented
  behaviour, migration, motivation, origin, or destination.** **Never link a bird to
  weather, wind, temperature, or sky** — "a swift drifted in on the westerly" is the
  canonical banned sentence. Weather and tide are ambient context, never causally attached.
- Counts and "first" claims come verbatim from the facts — never estimate, re-round, or
  embellish. Warmth lives in how true facts are joined ("the usual sparrows and magpies"),
  never in embellishing them. Restraint over enthusiasm; sentence case, no exclamation
  marks. **When unsure, leave it out.**
