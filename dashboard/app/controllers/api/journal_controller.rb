module Api
  # GET /api/journal?date=YYYY-MM-DD — a completed day's frozen diary entry: the final figures,
  # the warm narration and its citations, that day's new & notable, and the calendar bounds.
  # Defaults to yesterday (the last finished day); any date is clamped to what's available. The
  # entry itself is frozen once (JournalEntry) — figures and notable are recomputed from the
  # immutable detections on read. The stilled sparkline and the closing poem land in later phases.
  class JournalController < BaseController
    # The day's closing quotes, each SET APART with its credit — never woven into the
    # narration's prose. Two springs, in order: the station's curated literary lore (a
    # poem/tale from content/bird_lore.yml, one bird), then the day's SOURCED folklore
    # (dúchas and friends, via the enrichment bundles) for other prominent birds. Capped
    # so the foot of the page stays a coda, not an anthology.
    MAX_QUOTES = 2
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
        sparkline:  day_sparkline(facts),
        day_lore:   day_lore_json(date),
        notable:    notable_json(as_of: date, days: 1),
        quotes:     closing_quotes(facts),
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
    # living sparkline (rendered greyscale on the Journal). The whole day is treated as covered
    # (no live "mic down" bands on a finished day), so it's a clean curve.
    def day_sparkline(facts)
      counts = Array(facts[:activity_curve_24h]).pluck(:count)
      spark = Sparkline.paths(counts)
      { path: spark.path, fill: spark.fill, gaps: [], w: spark.w, h: spark.h }
    end

    # The day's Irish character (curated feast/quarter-day, else the Celtic season) as a bilingual
    # line + gloss. Factual — from the féilire reference, never narrated.
    def day_lore_json(date)
      entry = Feilire.for(date)
      { title: bilingual(entry['title']), gloss: bilingual(entry['gloss']), kind: entry['kind'] }
    end

    def closing_quotes(facts)
      items = Array(facts[:items]).sort_by { |i| -i[:importance].to_i }
      quotes = []
      curated_quote(items, facts[:date]) { |q| quotes << q }
      folklore_quotes(items, quotes)
      quotes.first(MAX_QUOTES)
    end

    def curated_quote(items, date)
      items.each do |item|
        lore = BirdLore.for(item[:sci_name], date: date)
        next unless lore

        name = BirdName.lookup(item[:sci_name])
        return yield({ kind: lore['kind'], text: lore['text'].to_s.strip, attribution: lore['attribution'],
                       sci: item[:sci_name], en: name.en, ga: name.ga })
      end
    end

    # Sourced folklore for birds that don't already carry a quote. The credit is the
    # source host (dúchas.ie etc.) — quoted material always says where it came from.
    def folklore_quotes(items, quotes)
      items.each do |item|
        break if quotes.size >= MAX_QUOTES
        next if quotes.any? { |q| q[:sci] == item[:sci_name] }

        block = EnrichmentBundle.current(item[:sci_name])&.block_objects&.find { |b| b.type == 'folklore' }
        next unless block

        name = BirdName.lookup(item[:sci_name])
        quotes << { kind: 'folklore', text: block.text.to_s.strip, text_ga: block.text_ga.presence,
                    attribution: block.sources.first&.dig(:host),
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
        summary: { en: [], ga: [] }, source: nil, sources: [], sparkline: nil, day_lore: nil,
        notable: notable_json(days: 1), quotes: [], available: { first: nil, last: Date.yesterday.iso8601 } }
    end
  end
end
