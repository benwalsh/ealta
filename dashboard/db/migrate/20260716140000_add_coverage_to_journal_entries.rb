class AddCoverageToJournalEntries < ActiveRecord::Migration[8.1]
  # Per-hour liveness for the completed day — 24 booleans, was the mic → BirdNET loop up that hour
  # — computed from heartbeats at freeze time while they still exist (heartbeats prune to ~2 days).
  # It lets the Journal draw honest "mic down" gaps and tell an OFFLINE day from a genuinely quiet
  # one. Nullable: unknown when the station sent no ticks, or a day frozen after the ticks pruned.
  # No literal default (MySQL rejects one on a JSON column); the model just leaves it nil.
  def change
    add_column :journal_entries, :coverage, :json
  end
end
