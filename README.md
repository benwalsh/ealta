# Ealta

*A self-hostable bird-detection wall display: it listens for birdsong, identifies
species acoustically with Cornell's BirdNET, and renders a calm, paper-like collage
of the flock on a framed e-ink panel — or in any browser.*

Every station is different, so Ealta is **configured, not forked**. Your place,
your languages, your curated lore, and which folklore/ornithology sources the writer
may cite all live in a **station profile** — a directory you point `STATION_PROFILE`
at. The code names no location and no language; it boots on a neutral example profile
out of the box, and you layer your own on top.

---

## How it works

```
outdoor mic ─▶ BirdNET (birdnetlib, Python) ─▶ detections (SQLite)
                                                    │
                                       ActiveRecord │ read-only
                                                    ▼
                            Rails dashboard  ──▶  /station (bare 800×480 SVG)
                        (mask-packed collage,          │
                         credibility-filtered)         │ Playwright screenshot
                                                       ▼
                                          dither to Spectra-6 ─▶ Inky e-ink panel
```

The split is deliberate: **detection stays Python** (BirdNET is a TensorFlow-Lite
model — reimplementing it buys nothing), the **dashboard is Rails + React** (the part
worth owning and enjoying), and the **Inky push is a thin Python shooter** (Pimoroni's
`inky` library is Python-only). The SQLite datastore is the contract between them.

## Repo layout

```
birdnet/          BirdNET listener — analyse a recording or the live mic into the DB
dashboard/        Rails + React web app — the dashboard and the e-ink /station page
pipeline/scripts/ illustration pipeline: pregen → cutout_flood → build_masks
pipeline/assets/  generated illustrations + masks.json (collage silhouettes)
shooter/          Playwright screenshot of /station → dither → push to the Inky
deploy/           systemd units + DEPLOY.md runbook
model/l18n/       stock BirdNET labels per language (labels_en.json, labels_ga.json, …)
stations/example/ the reference station profile the app falls back to
```

## Quickstart

Python is managed with [uv](https://docs.astral.sh/uv/); the web app is Rails 8 +
Hotwire + React (Vite), bundled with [bun](https://bun.sh). Copy `.env.example` to a
gitignored `.env` to start.

```bash
make setup          # install Python, Ruby, JS deps and prepare the database
make serve          # run the dashboard at http://localhost:4030
make listen         # listen on the mic and write detections (Ctrl-C to stop)
make analyze FILE=song.wav   # analyse a recorded clip instead of the mic
make frame-preview  # dither /station to a PNG to preview the Inky look (no hardware)
make test           # RSpec        ·   make lint   # RuboCop
make help           # list every task
```

With no `STATION_PROFILE` set, the app runs on `stations/example`: a nameless,
English-only station with a neutral illustration style and no external lore sources.

## Make it your own station

```bash
make new-station NAME=yourplace       # copies stations/example → stations/yourplace
# then edit stations/yourplace/ and point STATION_PROFILE at it in .env
```

A station profile is just files (everything optional — it falls back, per file, to the
example):

```
stations/yourplace/
  station.yml            place, url, site name, languages, admin emails
  prompts/*.md           the LLM voice: the daily-note, researcher and digest prompts
  content/bird_lore.yml  curated public-domain verse/tales per species (quoted verbatim)
  content/feilire.yml    a local calendar of notable days
  sources/allowlist.yml  which hosts the researcher may fetch + which adapters to enable
  image/prompt.template.md  the illustration style sent to the image model
```

Two design precepts hold across every station: an **e-ink voice everywhere** (restrained,
paper-like, one live gesture — the sparkline), and **rigorous factuality about birds**
(Ruby computes every count and claim; the model only narrates already-true facts, and
nothing unsourced ships). Keep them and your station will feel like Ealta.

## Multiple languages

BirdNET ships labels for ~30 languages under `model/l18n/`. A station's `languages:`
(in `station.yml`) picks its display language(s); English is always the base, and the
first other language you list becomes the bilingual second name. A single-language
station never translates. Curated content (`content/*.yml`, `prompts/*.md`) is yours to
write in whatever language fits.

## Deploy to a Raspberry Pi

`deploy/` holds the systemd units and [`deploy/DEPLOY.md`](deploy/DEPLOY.md), the runbook
for moving desktop → Pi: a `provision.sh` that goes flash → SSH → run → done, WAL +
Litestream offsite backup of the detections DB, the Inky driver install, and the final
on-glass colour/dither tuning. Remote access is Tailscale (outbound-only), not a public
service — the box keeps running everything itself.

## Lineage & license

Ealta is an original Rails/React + Python project — not a fork. It does two things
that carry an inherited licence:

- **Detection is Cornell's [BirdNET](https://birdnet.cornell.edu/)**, used through the
  [`birdnetlib`](https://github.com/joeweiss/birdnetlib) library. The model weights are
  downloaded at runtime, not redistributed here; BirdNET's species-label lists ship under
  `model/` (the Irish list, `labels_ga.json`, is derived from BirdWatch Ireland's names).
- **The `detections` table reuses [BirdNET-Pi](https://github.com/mcguirepr89/BirdNET-Pi)'s
  schema** (Patrick McGuire) column-for-column, as the on-device data contract.

It began, historically, from [AvianVisitors](https://github.com/Twarner491/AvianVisitors)
(built on BirdNET-Pi), but no upstream code remains: the PHP/shell layers were replaced by
this Rails app and a `birdnetlib` listener, and the detection model was rebuilt around
station profiles.

Licensed **CC BY-NC-SA 4.0**, inherited from BirdNET / BirdNET-Pi and binding as long as
the project uses BirdNET — attribution to the **Cornell Lab of Ornithology** (BirdNET),
**Patrick McGuire** (BirdNET-Pi), and **BirdWatch Ireland** (`labels_ga.json`). You may
run, study, and adapt it for **non-commercial** use; distributed adaptations must be
**shared alike** under the same licence. It is source-available on those terms, not an OSI
"open source" licence.
