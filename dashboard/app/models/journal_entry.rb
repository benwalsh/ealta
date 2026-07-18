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
      # The day's hero, frozen alongside the prose so the letter, the web coda and every later
      # view feature the same bird — and so tomorrow's anti-repetition can read who led today.
      hero = DayHero.pick(facts[:items], as_of: date)
      narration = DayNarrator.narrate(facts, hero: hero).slice(:bullets, :source, :sources)
      # Freeze the day's per-hour coverage now, while heartbeats still exist, so the Journal can
      # draw honest mic-down gaps and tell an offline day from a quiet one on any later read.
      attrs = narration.merge(hero_sci_name: hero&.dig(:sci_name), coverage: facts[:coverage_24h])
      # A thin 'template' narration is left UNsaved so a later view can retry it into a real entry
      # (enrich is the sweep's job; on-read we narrate from whatever bundles exist) — but only on a
      # day that HAS detections, i.e. a transient model/enrichment gap. A day with NONE will never
      # narrate to more, so we freeze it, coverage and all, to record whether the station was
      # offline that day rather than genuinely quiet — a distinction that's lost once heartbeats prune.
      return new(date: date, **attrs) if attrs[:source] == 'template' && facts[:detections_today].to_i.positive?

      create_or_find_by!(date: date) { |entry| entry.assign_attributes(attrs) }
    end
  end
end
