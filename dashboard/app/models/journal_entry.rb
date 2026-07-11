class JournalEntry < ApplicationRecord
  # A frozen diary entry for one completed day. Built once — narrated by DayNarrator over that
  # day's DailyFacts + stored lore — then never regenerated (a completed day can't change). Only
  # the model's prose is stored; the day's figures and sparkline are recomputed from the
  # immutable detections on read. The Journal is the warm, past-tense counterpart to Live.

  # Defaults at the model, not the DB: MySQL forbids a literal default on a JSON column and the
  # SQLite schema dump can't round-trip an expression one, so these are `null: false` with no DB
  # default and start empty here.
  attribute :bullets, default: -> { {} }
  attribute :sources, default: -> { [] }

  validates :date, presence: true, uniqueness: true

  class << self
    # The entry for a completed day (defaults to yesterday, the last finished one). Returns the
    # frozen row, building + freezing it on first request — the universal safety net, working the
    # same on the Pi and the cloud. Never today or the future (an unfinished day → nil). A weak
    # 'template' narration (nothing to say yet, or a transient model outage) is returned
    # UNsaved so a later view can retry into a real entry rather than freezing the thin one.
    def for(date = Date.yesterday)
      date = date.to_date
      return nil unless date < Date.current

      find_by(date: date) || build_and_freeze(date)
    end

    private

    def build_and_freeze(date)
      facts = DailyFacts.for(date: date, now: date.end_of_day)
      attrs = DayNarrator.narrate(facts).slice(:bullets, :source, :sources)
      # enrich is the sweep's job (it runs Enrichment::Builder first); on-read we narrate from
      # whatever bundles already exist, so a public view never blocks on live sourcing.
      return new(date: date, **attrs) if attrs[:source] == 'template'

      create_or_find_by!(date: date) { |entry| entry.assign_attributes(attrs) }
    end
  end
end
