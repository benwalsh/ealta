# Ealta — local dev tasks. Run from the repo root.
# `make` or `make help` lists everything. Config lives in .env (gitignored).
.ONESHELL:
SHELL := /bin/bash

PORT ?= 4030
POSES ?= 1

.PHONY: help setup new-station serve listen analyze regen restyle cutout declutter masks build doctor armcheck test lint

help:  ## list the available tasks
	@grep -hE '^[a-z][a-zA-Z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## / — /' | sort

setup:  ## install all deps (Python, Ruby, JS) and prepare the database
	uv sync
	cd dashboard && bundle install && bun install && bin/rails stimulus:manifest:update && bin/vite build && bin/rails db:prepare

new-station:  ## scaffold your own station profile:  make new-station NAME=yourplace
	@test -n "$(NAME)" || { echo "usage: make new-station NAME=yourplace"; exit 1; }
	@test ! -e stations/$(NAME) || { echo "stations/$(NAME) already exists"; exit 1; }
	cp -r stations/example stations/$(NAME)
	@echo "created stations/$(NAME) — edit its station.yml, then set STATION_PROFILE=$(CURDIR)/stations/$(NAME) in .env"

serve:  ## run the collage web app  (override with: make serve PORT=4030)
	set -a; source .env; set +a; \
	cd dashboard && bin/rails server -p $(PORT)

# NB: lines are joined with `\` so `source .env` and the command share one shell.
# macOS ships GNU Make 3.81, which ignores .ONESHELL, so each bare line would
# otherwise run in its own shell and lose the sourced env.
listen:  ## listen on the mic: write detections + liveness heartbeats, mirror to cloud as it goes (Ctrl-C to stop)
	set -a; source .env; set +a; \
	uv run python birdnet/listen.py listen

push:  ## push new local detections + heartbeats up to the cloud mirror (reads CLOUD_INGEST_* from .env)
	set -a; source .env; set +a; \
	uv run python birdnet/push.py

analyze:  ## analyse a recording:  make analyze FILE=path/to/song.wav
	set -a; source .env; set +a; \
	uv run python birdnet/listen.py recording "$(FILE)"

regen:  ## regenerate one bird's art:  make regen SPECIES="Corvus monedula|Eurasian Jackdaw"
	set -a; source .env; set +a; \
	uv run python pipeline/scripts/pregen.py --species "$(SPECIES)" --poses 1 --force && \
	uv run python pipeline/scripts/cutout_flood.py

cutout:  ## flood-cut any cream-ground illustrations to transparent
	uv run python pipeline/scripts/cutout_flood.py

declutter:  ## sweep stray flecks ("smudges") from existing cutouts, then rebuild masks
	uv run python pipeline/scripts/cutout_flood.py --declutter
	uv run python pipeline/scripts/build_masks.py

masks:  ## rebuild collage silhouette masks (run after changing the illustration set)
	uv run python pipeline/scripts/build_masks.py

restyle:  ## redraw the whole Irish library in the current prompt style, then cut + remask  (POSES="1 2" adds flight)
	set -a; source .env; set +a; \
	uv run python pipeline/scripts/irish_labels.py > /tmp/irish-labels.txt; \
	echo "restyling $$(grep -c . /tmp/irish-labels.txt) Irish species (poses $(POSES))..."; \
	uv run python pipeline/scripts/pregen.py --labels /tmp/irish-labels.txt --poses $(POSES) --force && \
	uv run python pipeline/scripts/cutout_flood.py && \
	uv run python pipeline/scripts/build_masks.py

frame-preview:  ## dither /station to a PNG to inspect the Inky look (no hardware)
	uv run python shooter/shoot.py --url http://localhost:$(PORT)/station --preview $(or $(OUT),frame.png)

frame:  ## push the panel to the Inky  (Pi only)
	uv run python shooter/shoot.py --url http://localhost:$(PORT)/station

purge:  ## clear all detections (reset the collage to empty)
	cd dashboard && bin/rails runner 'puts "cleared #{Detection.delete_all} detections"'

build:  ## register Stimulus controllers + build the Vite bundle (JS + React SPA)
	cd dashboard && bin/rails stimulus:manifest:update && bin/vite build

doctor:  ## verify the Python<->Rails<->datastore seams + Irish locale (bring-up check)
	cd dashboard && bin/rails ealta:doctor

armcheck:  ## validate the macOS->Pi gap in an arm64 Debian container (deps, native gem builds, Irish locale)
	docker build -f deploy/Dockerfile.armcheck -t ealta-armcheck .
	docker run --rm ealta-armcheck

test:  ## run the Rails specs
	cd dashboard && bin/rspec

lint:  ## lint everything — Ruby (RuboCop), Python (ruff), JS/TS (ESLint + tsc + Prettier)
	uv run --with ruff ruff check birdnet pipeline/scripts shooter
	uv run --with ruff ruff format --check birdnet pipeline/scripts shooter
	( cd dashboard && bin/rubocop && bunx eslint app/javascript && bunx tsc --noEmit && bunx prettier --check app/javascript )

fmt:  ## autoformat + autofix everything (Ruby, Python, JS/TS)
	uv run --with ruff ruff check --fix birdnet pipeline/scripts shooter
	uv run --with ruff ruff format birdnet pipeline/scripts shooter
	( cd dashboard && bin/rubocop -a && bunx eslint app/javascript --fix && bunx prettier --write app/javascript )
