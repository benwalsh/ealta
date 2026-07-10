class CreateEnrichmentTables < ActiveRecord::Migration[8.1]
  # Caches for the daily enrichment pipeline. Cloud-only in practice (Claude/Nova +
  # network live there), but harmless on SQLite so the whole pipeline is dev-testable.
  def change
    # One bundle per (species, date) that cleared the notability gate — the unit
    # Claude produces and Nova consumes. The unique index IS the per-species-per-day
    # crawl cap: a second enrichment pass is a no-op upsert, not more network hits.
    create_table :enrichment_bundles do |t|
      t.string :sci_name, null: false
      t.date :date, null: false
      t.string :common_name
      t.string :irish_name
      t.json :blocks, null: false, default: -> { '(JSON_ARRAY())' }
      t.string :source_run_id
      t.timestamps
    end
    add_index :enrichment_bundles, %i[sci_name date], unique: true

    # Politeness ledger: one row per outbound hit to a cultural/scientific source,
    # so we can prove at a glance we hit dúchas once for the cuckoo, not fifty times.
    # rubocop:disable Rails/CreateTableWithTimestamps -- append-only ledger; `fetched_at`
    # is the event time, created_at/updated_at would be redundant.
    create_table :source_fetch_logs do |t|
      t.string :host, null: false
      t.string :url
      t.string :sci_name
      t.datetime :fetched_at, null: false
      t.string :run_id
    end
    # rubocop:enable Rails/CreateTableWithTimestamps
    add_index :source_fetch_logs, %i[sci_name fetched_at]
  end
end
