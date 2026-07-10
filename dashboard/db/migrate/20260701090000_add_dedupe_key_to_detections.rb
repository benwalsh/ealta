class AddDedupeKeyToDetections < ActiveRecord::Migration[8.1]
  # An idempotent key for the cloud mirror's ingest: re-POSTing a batch after a
  # partial outage must not double-insert. There's no natural unique key (two
  # calls of one species in the same second are indistinguishable), so the Pi's
  # push script sends SHA-256 of Date|Time|Sci_Name|Confidence|File_Name and the
  # cloud upserts on it. Runs on both adapters — a nullable column + a unique
  # index that tolerates many NULLs — so ingest is testable in dev SQLite; on the
  # Pi it simply stays NULL, unused by the listener.
  def change
    add_column :detections, :dedupe_key, :string
    add_index :detections, :dedupe_key, unique: true
  end
end
