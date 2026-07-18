module Api
  # GET /api/journal?date=YYYY-MM-DD — a completed day's frozen diary entry: the final figures,
  # the warm narration and its citations, that day's new & notable, and the calendar bounds.
  # Defaults to yesterday (the last finished day); any date is clamped to what's available. The
  # entry itself is frozen once (JournalEntry) — figures and notable are recomputed from the
  # immutable detections on read. The stilled sparkline and the closing poem land in later phases.
  class JournalController < BaseController
    def show
      date = journal_date
      return render(json: unavailable) unless date

      entry = JournalEntry.for(date)
      facts = DailyFacts.for(date: date, now: date.end_of_day)
      render json: {
        date:       date.iso8601,
        date_label: TodayCard.date_label(date.in_time_zone),
        figures:    figures_json(facts),
        summary:    { en: TodayCard.emphasised_bullets(entry_bullets(entry, 'en'), facts, :en),
                      ga: TodayCard.emphasised_bullets(entry_bullets(entry, 'ga'), facts, :ga) },
        source:     entry&.source,
        sources:    entry_sources(entry),
        # The keeper's own line for the day — the same note the letter carries, so the letter
        # and the journal stay the same words. nil on almost every day.
        note:       DayNote.body_for(date),
        sparkline:  day_sparkline(facts, entry),
        offline:    day_offline?(entry),
        mic_hours:  mic_hours(entry),
        day_lore:   day_lore_json(date),
        hero:       HeroCard.for(entry&.hero_sci_name),
        notable:    notable_json(as_of: date, days: 1),
        quotes:     closing_quotes(facts, entry),
        available:  available_bounds
      }
    end

    private

    # The requested day, clamped to [first detection … yesterday]; nil when there is no
    # completed day yet (an empty or brand-new station).
    def journal_date
      first = first_detection_date
      return nil if first.nil? || first > Date.yesterday

      (parse_date(params[:date]) || Date.yesterday).clamp(first, Date.yesterday)
    end

    def figures_json(facts)
      loudest = Array(facts[:items]).max_by { |i| i[:call_count] }
      {
        species:    facts[:species_today],
        detections: facts[:detections_today],
        busiest:    loudest && { sci: loudest[:sci_name], en: loudest[:common_name],
                                 ga: loudest[:irish_name], count: loudest[:call_count] }
      }
    end

    # The completed day's 24h activity curve as ready SVG paths — the *stilled* twin of Live's
    # living sparkline (rendered greyscale on the Journal). It carries the day's frozen coverage, so
    # hours the mic was down draw as honest "no data" gaps (an offline stretch), not a false zero.
    # nil coverage (unknown — an old day past heartbeat retention) falls back to a clean, covered
    # curve.
    def day_sparkline(facts, entry)
      counts = Array(facts[:activity_curve_24h]).pluck(:count)
      spark = Sparkline.paths(counts, coverage: entry&.coverage)
      { path: spark.path, fill: spark.fill, gaps: day_gap_labels(spark.gaps), w: spark.w, h: spark.h }
    end

    # Sparkline gap bands → bilingual "No data · HH:00–HH:00" labels. The 24 buckets are whole
    # hours, so a band's from/to indices are the clock hours directly.
    # The blind-spot bands as bare x-spans. No captions: nothing is painted over a gap now —
    # the curve breaks there, and a wholly uncovered day draws no path at all — so there is
    # no slab to label. `offline` / `mic_hours` state the same fact in words.
    def day_gap_labels(gaps)
      Array(gaps).map { |g| { x0: g[:x0], x1: g[:x1] } }
    end

    # Was the station down for most of the day — so a zero-detection day reads as OFFLINE, not as a
    # genuinely quiet one. False when coverage is unknown (drawn as covered).
    def day_offline?(entry)
      coverage = entry&.coverage
      coverage.present? && coverage.count { |up| up } < coverage.size / 2
    end

    # How many of the day's 24 hours the mic → BirdNET loop was actually up (a heartbeat tick or a
    # detection proves the hour live). Lets a zero-detection day say honestly how long it listened —
    # "the mic recorded 3 of 24 hours" (offline) vs "listened all day and logged nothing" (quiet) —
    # rather than blurring the two. nil when coverage is unknown (an old day past heartbeat retention,
    # or a station that has never ticked), where we can't claim any listening time.
    def mic_hours(entry)
      coverage = entry&.coverage
      coverage.present? ? coverage.count { |up| up } : nil
    end

    # The day's Irish character (curated feast/quarter-day, else the Celtic season) as a bilingual
    # line + gloss. Factual — from the féilire reference, never narrated.
    def day_lore_json(date)
      entry = Feilire.for(date)
      { title: bilingual(entry['title']), gloss: bilingual(entry['gloss']), kind: entry['kind'],
        # A curated deep dive on the day's tradition (bird_lore-style, facts-only) when the station
        # supplies one — a longer bilingual passage + optional citations. nil/[] on a plain day.
        lore: entry['lore'] && bilingual(entry['lore']),
        sources: Array(entry['sources']).filter_map { |s| s['url'].present? && { host: s['host'], url: s['url'] } } }
    end

    # The entry closes on a SINGLE folklore quote — one direct quotation, SET APART with its
    # credit, never woven into the narration. It follows the day's frozen HERO (JournalEntry, chosen
    # by DayHero — importance with anti-repetition), so the coda features the same bird as the
    # letter's picture, and a golden plover's first visit takes it over the everyday sparrow. The
    # folklore itself is one spring: the station's own curated poems/tales (bird_lore.yml) and the
    # web-sourced folklore (dúchas and friends) come back together from EnrichmentBundle.folklore_for,
    # indistinguishable once here. (Folklore inside a Wikipedia FACT is not this — it stays a fact.)
    # The hero's own entries rotate by the day, so a bird leading several days running doesn't repeat
    # the same poem; the pick stays fixed for any given past date. Empty when the hero carries no
    # folklore — the hero is still featured elsewhere (picture, deep dive); it just has nothing to
    # quote.
    def closing_quotes(facts, entry)
      sci = entry&.hero_sci_name
      return [] if sci.blank?

      item = Array(facts[:items]).find { |i| i[:sci_name] == sci }
      return [] unless item

      quotes = folklore_quotes(item)
      return [] if quotes.empty?

      [quotes[facts[:date].to_date.jd % quotes.size]]
    end

    # A bird's folklore as set-apart quotes — seed and sourced alike, in one shape, each credited
    # by its source (the seed entry's attribution, the web block's host). `attribution` stays the
    # plain reference string; `source` carries the full citation (url + rights-holder + licence deed
    # + collector) so a dúchas coda renders the exact attribution the Schools' Collection asks for.
    def folklore_quotes(item)
      name = BirdName.lookup(item[:sci_name])
      EnrichmentBundle.folklore_for(item[:sci_name]).map do |block|
        src = block.sources.first || {}
        { kind: 'folklore', text: block.text.to_s.strip, text_ga: block.text_ga.presence,
          attribution: src[:host],
          source: { host: src[:host], url: src[:url], holder: src[:holder], licence: src[:licence],
                    licence_url: src[:licence_url], collector: src[:collector] }.compact.presence,
          sci: item[:sci_name], en: name.en, ga: name.ga }
      end
    end

    def bilingual(hash)
      { en: hash['en'], ga: hash['ga'] }
    end

    def available_bounds
      { first: first_detection_date&.iso8601, last: Date.yesterday.iso8601 }
    end

    def first_detection_date
      @first_detection_date ||= Detection.minimum(:Date)&.to_date
    end

    def entry_bullets(entry, lang)
      Array(entry&.bullets&.with_indifferent_access&.dig(lang))
    end

    def entry_sources(entry)
      Array(entry&.sources).map { |s| s.with_indifferent_access.then { |h| { host: h[:host], url: h[:url] } } }
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    # A well-formed empty payload for a station with no completed day yet — the tab still
    # renders (an "ag éisteacht…" state) rather than erroring.
    def unavailable
      { date: nil, date_label: { en: '', ga: '' }, figures: { species: 0, detections: 0, busiest: nil },
        summary: { en: [], ga: [] }, source: nil, sources: [], sparkline: nil, offline: false,
        mic_hours: nil,
        day_lore: nil, hero: nil, notable: notable_json(days: 1), quotes: [],
        available: { first: nil, last: Date.yesterday.iso8601 } }
    end
  end
end
