# Wipe the detection history and everything derived from it — the admin "start fresh" button,
# behind a typed confirmation so it can't be a stray click. Clears the time-series (detections,
# events, heartbeats, journal entries) but KEEPS the costly per-species enrichment caches
# (EnrichmentBundle, SpeciesInfo) and all config/users. Replaces scripts/clear_all_data.sh and
# widens `make purge` (which cleared detections only).
class DataReset
  CONFIRM = 'DELETE'.freeze
  MODELS = [Detection, Event, Heartbeat, JournalEntry].freeze

  class << self
    def clear!(confirm:)
      return { ok: false, message: "type #{CONFIRM} to confirm" } unless confirm.to_s == CONFIRM

      counts = MODELS.to_h { |model| [model.table_name.to_sym, model.delete_all] }
      { ok: true, message: "cleared #{counts[:detections]} detections and derived history", counts: counts }
    end
  end
end
