# Detection seeding is PERMANENTLY DISABLED.
#
# This file used to inject fake sample detections for desktop development — and,
# worse, it ran `Detection.where(Date: Date.current).delete_all` first, so every
# run DELETED the current day's REAL listener recordings before overlaying fakes.
# Run via `db:seed` / `db:reset` / a fresh `db:prepare`, it polluted (and partly
# destroyed) real data on the dev machine.
#
# Real detections come ONLY from the live listener (mic) locally, or from ingest
# in the cloud. Nothing here may ever create or delete detections again.
#
# If sample data is ever genuinely wanted, do it deliberately against a brand-new
# EMPTY database via an explicit opt-in task — never here, never with delete_all,
# never against a populated DB.

puts 'seeds: disabled — real detections come from the birdnet/ingest, never from seeds' # rubocop:disable Rails/Output
