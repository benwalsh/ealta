require 'json'

# The home page's daily "today" note — the today-day cache over DayNarrator. DayNarrator does
# all the reasoning and stitching (see it); this layer only decides when to regenerate and
# keeps the last-good result on disk so the page never blocks on the model.
#
# The page always reads the last-good cache (`current`). A scheduled/lazy `refresh` regenerates
# (~30-min cache). If the model is unreachable the last-good summary stays; only when there is
# no cache at all do we fall through to DayNarrator's deterministic fallback. So warmth never
# costs accuracy or availability. (Completed past days are the Journal's job — see JournalEntry,
# which freezes DayNarrator's output per date instead of caching a single slot.)
class TodaySummary
  STORE = Rails.root.join('storage/today_summary.json')

  class << self
    # The last-good summary for the page — bilingual { en: [...], ga: [...] }. A pure cache read:
    # it never narrates and never blocks, so it is safe on the request path. The cache is only
    # used for the SAME day we're rendering; a summary left over from yesterday is discarded so
    # "today" is never stale. On a miss it returns a bare placeholder the card hides — narration
    # (even the no-model fallback) is the warm job's work, off the request (WarmTodaySummaryJob,
    # enqueued by BaseController#warm_today_summary), so no visitor ever pays for it.
    def current(facts: nil)
      facts ||= DailyFacts.for
      cached = read_cache
      return cached if cached && cached[:facts_date].to_s == facts[:date].to_s

      { bullets: { en: [], ga: [] }, source: 'template', sources: [],
        facts_date: facts[:date], generated_at: nil }
    end

    # Regenerate and cache. Best-effort: when the model wrote it — or no model is coming at
    # all (unconfigured or disabled), so the facts fallback IS the note — store the fresh
    # result; when a model call was attempted but failed, keep the last-good cache rather
    # than overwriting it, and only synthesise a fresh fallback when there is nothing cached.
    # `enrich: false` skips the (slower) sourcing step for the page-load path.
    def refresh(now: Time.current, enrich: true)
      facts = DailyFacts.for(now: now)
      result = DayNarrator.narrate(facts, enrich: enrich)
      return store(result, facts) if result[:source] == 'llm' || !Bedrock.available?
      return current(facts: facts) if valid_cache_for?(facts)

      store(result, facts)
    end

    # Regenerate when the cache is missing, older than max_age, OR for a previous day (a new
    # day is always stale). Cheap to call on every ingest.
    def refresh_if_stale(max_age: 30.minutes, now: Time.current, enrich: true)
      cached = read_cache
      return cached unless stale?(max_age: max_age, now: now)

      refresh(now: now, enrich: enrich)
    end

    # Would refresh_if_stale do work? A pure read (one small file), so it is safe to ask on
    # every request — which is what lets a web request DECIDE to refresh without being the
    # thing that refreshes. See Api::BaseController#warm_today_summary.
    def stale?(max_age: 30.minutes, now: Time.current)
      cached = read_cache
      fresh = cached && cached[:generated_at] && cached[:generated_at] > max_age.ago &&
              cached[:facts_date].to_s == now.to_date.to_s
      !fresh
    end

    private

    # Is there a cache, and is it for the day we're about to render? Guards refresh's
    # keep-last-good path so a generation failure never resurrects yesterday's summary.
    def valid_cache_for?(facts)
      cached = read_cache
      cached.present? && cached[:facts_date].to_s == facts[:date].to_s
    end

    def read_cache
      return nil unless STORE.exist?

      data = JSON.parse(STORE.read, symbolize_names: true)
      # Bilingual shape only — a legacy flat-array cache (pre-bilingual) is treated as
      # absent, so it's discarded rather than shown monolingual.
      bullets = data[:bullets]
      return nil unless bullets.is_a?(Hash)

      en = Array(bullets[:en]).compact_blank
      return nil if en.empty?

      ga = Array(bullets[:ga]).compact_blank.presence || en
      { bullets: { en: en, ga: ga }, source: data[:source], sources: Array(data[:sources]),
        facts_date: data[:facts_date], generated_at: safe_time(data[:generated_at]) }
    rescue JSON::ParserError, SystemCallError
      nil
    end

    # Persist a DayNarrator result for the day and return it in the read shape.
    def store(result, facts)
      data = { bullets: result[:bullets], source: result[:source], sources: result[:sources],
               facts_date: facts[:date], generated_at: Time.current.iso8601 }
      STORE.dirname.mkpath # storage/ is runtime state — create it rather than ENOENT
      tmp = STORE.sub_ext('.tmp')
      tmp.write(JSON.pretty_generate(data))
      tmp.rename(STORE.to_s) # atomic replace so a reader never sees a half-written file
      { bullets: result[:bullets], source: result[:source], sources: result[:sources],
        facts_date: facts[:date], generated_at: safe_time(data[:generated_at]) }
    end

    def safe_time(value)
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
