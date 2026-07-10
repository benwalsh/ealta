class AddDedupeKeyToHeartbeats < ActiveRecord::Migration[8.1]
  # Mirrors detections' dedupe_key: the cloud ingest upserts heartbeats on a SHA-256 of
  # at|source that push.py sends, so a retried batch after an outage never double-inserts.
  # Both adapters (a nullable column + a NULL-tolerant unique index) so ingest is testable
  # in dev SQLite; on the Pi it simply stays NULL, unused by the listener's own writes.
  def change
    add_column :heartbeats, :dedupe_key, :string
    add_index :heartbeats, :dedupe_key, unique: true
  end
end
