# Collage — the display

The Rails web app that renders the bird collage. It reads the BirdNET detections
in `birds.db` (read-only, via ActiveRecord) and draws the flock; the
[shooter](../shooter) screenshots its `/panel` route and pushes that to the Inky.
Run everything from the repo root with `make` (see the [top-level
README](../README.md)) — this directory is just the Rails part.

## Stack & conventions

Rails 8.1 · Hotwire (Turbo + Stimulus) · HAML views · Propshaft · JS bundled with
**bun** (not yarn) via jsbundling · SQLite (WAL on the Pi). Tests are **RSpec +
FactoryBot + shoulda-matchers**; lint is **RuboCop** (the sibling work repo's
config, minus GraphQL). Binstubs in `bin/`. After adding a Stimulus controller,
`bin/rails stimulus:manifest:update && bun run build` (folded into `make build`).

## Run & test

```bash
make serve        # http://localhost:4030   (or: cd dashboard && bin/rails server)
make test         # bundle exec rspec
make lint         # bundle exec rubocop
```

## Layout

- **Views** — `collage` (the flock + `/panel`), `stats` (bar chart + lists),
  `atlas` (field-guide grid), `species` (the detail modal, a Turbo Frame).
- **`Detection`** (`app/models`) — reads `birds.db`; `tally_within`, `life_list`,
  and the `credible_species` display gate (confident-or-repeated species only).
- **`MaskPacker` / `BirdMask`** (`app/services`) — silhouette nesting from
  `masks.json`; **`CollagePresenter`** sizes and lays out the flock.
- **`BirdName` / `SpeciesInfo`** — bilingual names from `model/l18n/labels_*.json`
  and cached English/Irish Wikipedia descriptions for the modal.

## Configuration

No app config of its own — it inherits the repo `.env`. Set `BIRD_DB` to point at
a different `birds.db`; in development it defaults to `storage/development.sqlite3`,
which the listener also writes. Ngrok hosts are allowed in `development.rb` for
phone testing.
