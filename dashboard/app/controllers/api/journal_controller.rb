module Api
  # GET /api/journal?date=YYYY-MM-DD — a completed day's frozen diary entry: the final figures,
  # the warm narration and its citations, that day's new & notable, and the calendar bounds.
  # Defaults to yesterday (the last finished day); any date is clamped to what's available. The
  # entry itself is frozen once (JournalEntry) — figures and notable are recomputed from the
  # immutable detections on read. The stilled sparkline and the closing poem land in later phases.
  class JournalController < BaseController
    # How many of the day's birds (hero first, then importance order) to check for folklore before
    # giving up on a closing quote — bounds the lookup while covering every prominent bird.
    LORE_CANDIDATES = 12

    # How many species the day's "heard" roll carries — the same cap as Live's Recently heard
    # (overview#show), so the two lists read as one section in two tenses.
    HEARD_LIMIT = 12

    # Editorial lead-ins a folklore block sometimes opens with — "In a tale from the Schools'
    # Collection,", "According to folklore,", and kin. The source is cited separately (LoreCredit),
    # so the quote should stand on its own as the lore itself; strip the meta-frame and re-capitalise
    # what's left (see strip_lore_framing). Best-effort clean-up of already-stored text — the
    # enrichment prompt now asks for the lore DIRECTLY, so freshly sourced folklore arrives clean.
    LORE_FRAMES = [
      /\AIn (?:a|one) (?:tale|story|legend|account)\b[^,.]*[,.]\s*/i,
      /\AA (?:tale|story|legend)\b[^,.]*?(?:tells|recounts|relates|holds|has it)\b[^,.]*?(?:how|that)\s+/i,
      /\AAccording to (?:the Schools'? Collection|tradition|folklore|legend|one (?:tale|story))\b[^,.]*[,.]\s*/i,
      /\AIn (?:the Schools'? Collection|Irish folklore|folklore|tradition|legend|one (?:tale|story))\b[^,.]*[,.]\s*/i,
      /\A(?:Tradition|Folklore|Legend|Lore) (?:holds|has it|tells us|says)\s+that\s+/i,
      # Irish equivalents (a light touch — the prompt fix is the durable one).
      /\AI (?:scéal|seanscéal)\b[^,.]*[,.]\s*/i,
      /\ADe réir (?:an bhéaloidis|na seanchais|Bhailiúchán na Scol)\b[^,.]*[,.]\s*/i
    ].freeze

    # Friendly citation names for the common hosts (mirrors SourceCitations.tsx); anything else
    # shows its bare domain (see source_label).
    HOST_LABEL = {
      'duchas.ie' => 'dúchas.ie', 'www.duchas.ie' => 'dúchas.ie', 'celt.ucc.ie' => 'CELT',
      'en.wikipedia.org' => 'Wikipedia', 'ga.wikipedia.org' => 'Vicipéid',
      'birdwatchireland.ie' => 'BirdWatch Ireland', 'www.birdwatchireland.ie' => 'BirdWatch Ireland',
      'irbc.ie' => 'Irish Rare Birds Committee', 'iwt.ie' => 'Irish Wildlife Trust',
      'biodiversityireland.ie' => 'Biodiversity Ireland', 'irishheritagenews.ie' => 'Irish Heritage News'
    }.freeze

    def show
      date = journal_date
      return render(json: unavailable) unless date

      entry = JournalEntry.for(date)
      facts = DailyFacts.for(date: date, now: date.end_of_day)
      cites = citation_map(facts)
      render json: {
        date:       date.iso8601,
        date_label: TodayCard.date_label(date.in_time_zone),
        figures:    figures_json(facts, entry),
        heard:      heard_json(date),
        summary:    { en: TodayCard.emphasised_bullets(entry_bullets(entry, 'en'), facts, :en, cites: cites),
                      ga: TodayCard.emphasised_bullets(entry_bullets(entry, 'ga'), facts, :ga, cites: cites) },
        source:     entry&.source,
        sources:    entry_sources(entry),
        # The keeper's own line for the day — the same note the letter carries, so the letter
        # and the journal stay the same words. nil on almost every day.
        note:       DayNote.body_for(date),
        sparkline:  day_sparkline(facts, entry),
        offline:    day_offline?(entry),
        mic_hours:  mic_hours(entry),
        day_lore:   day_lore_json(date),
        # A rotating local-colour story from the station's own ground (place_lore.yml) — the coast's
        # standing character, and the carry for a birdless winter day. nil when the station ships none.
        place:      PlaceLore.for(date),
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

    def figures_json(facts, entry)
      loudest = Array(facts[:items]).max_by { |i| i[:call_count] }
      {
        species:          facts[:species_today],
        detections:       facts[:detections_today],
        # The time the mic was actually listening that day, gaps taken out (whole hours — the
        # day's frozen coverage is hourly). nil when coverage is unknown (an old day past
        # heartbeat retention), where we can't claim any listening time.
        duration_seconds: day_listening_seconds(entry),
        busiest:          loudest && { sci: loudest[:sci_name], en: loudest[:common_name],
                                 ga: loudest[:irish_name], count: loudest[:call_count] }
      }
    end

    # The day's listening time in seconds, from its frozen hourly coverage: one live hour = 3600s.
    # nil when coverage is unknown, so the stats block can drop the duration rather than show a zero.
    def day_listening_seconds(entry)
      coverage = entry&.coverage
      coverage.present? ? coverage.count { |up| up } * 3600 : nil
    end

    # The day's birds, last-heard first — Live's "Recently heard" locked to one finished day.
    # Same shape as overview#show's `recent` (tally_json), so both surfaces render from the same
    # component; only the meta differs (a clock time here, time-ago there). Capped like Live's,
    # so a loud day doesn't turn the journal's closing figures into a wall of names.
    def heard_json(date)
      Detection.tally_for(date).
        sort_by { |t| t.last_time.to_s }.
        last(HEARD_LIMIT).reverse.
        map { |t| tally_json(t) }
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
        # The RICH layer: a curated custom/belief/legend fixed to this day (day_lore.yml). Takes
        # precedence over the felire_lore floor. nil on the many days with no curated lore.
        day: DayLore.for(date),
        # The FLOOR: the day's saint(s) and verse from felire_lore.yml (Martyrology of Óengus) —
        # shown when the day has no rich `day` lore. nil on a source-gap day (→ season fallback).
        narrative: FeilireLore.for(date),
        sources: Array(entry['sources']).filter_map { |s| s['url'].present? && { host: s['host'], url: s['url'] } } }
    end

    # The entry closes on a SINGLE folklore quote — one direct quotation, SET APART with its
    # credit, never woven into the narration. It follows the day's frozen HERO (JournalEntry, chosen
    # by DayHero — importance with anti-repetition), so the coda features the same bird as the
    # letter's picture, and a golden plover's first visit takes it over the everyday sparrow. The
    # folklore itself is one spring: the station's own curated poems/tales (bird_lore.yml) and the
    # web-sourced folklore (dúchas and friends) come back together from EnrichmentBundle.folklore_for,
    # indistinguishable once here. (Folklore inside a Wikipedia FACT is not this — it stays a fact.)
    # The pick PREFERS the day's frozen HERO (JournalEntry, chosen by DayHero — importance with
    # anti-repetition), so the coda usually features the same bird as the letter's picture. But some
    # heroes have no lore at all (a common scoter, say), so we fall through to the day's other birds
    # in importance order — the journal should almost always close on a piece of lore. Empty only when
    # nothing heard that day has any. A bird's own entries rotate by the day so a repeat doesn't show
    # the same poem; the pick stays fixed for any given past date.
    def closing_quotes(facts, entry)
      items = Array(facts[:items])
      hero = items.find { |i| i[:sci_name] == entry&.hero_sci_name }
      ([hero].compact + items).uniq { |i| i[:sci_name] }.first(LORE_CANDIDATES).each do |item|
        quotes = folklore_quotes(item)
        next if quotes.empty?

        return [quotes[facts[:date].to_date.jd % quotes.size]]
      end
      []
    end

    # A bird's folklore as set-apart quotes — seed and sourced alike, in one shape, each credited
    # by its source (the seed entry's attribution, the web block's host). `attribution` stays the
    # plain reference string; `source` carries the full citation (url + rights-holder + licence deed
    # + collector) so a dúchas coda renders the exact attribution the Schools' Collection asks for.
    # A CURATED literary entry (bird_lore.yml) carries more — a title, a set-apart verse, a context
    # note, and a book citation — which ride through here for the Bird Lore & Wisdom block; its text
    # is verbatim (never framing-stripped, that's for scraped passages), and its `kind` (poem/legend/
    # belief/tale) drives the styling.
    def folklore_quotes(item)
      name = BirdName.lookup(item[:sci_name])
      EnrichmentBundle.folklore_for(item[:sci_name]).map do |block|
        src = block.sources.first || {}
        attrs = block.to_h
        curated = block.id.to_s.start_with?('seed-')
        { kind: attrs[:lore_kind].presence || 'folklore',
          title: attrs[:title],
          text: curated ? block.text.to_s.strip.presence : strip_lore_framing(block.text.to_s.strip).presence,
          text_ga: curated ? block.text_ga.presence : strip_lore_framing(block.text_ga).presence,
          # A set-apart verse quotation inside a prose entry (or the whole of a verse-only entry).
          quote: attrs[:quote].presence,
          # Reader-facing context for the piece — kept apart from the verse, never woven in.
          note: attrs[:note].presence,
          # The composed book citation for curated lore; web folklore falls back to attribution/source.
          credit: attrs[:credit].presence,
          attribution: src[:host],
          source: { host: src[:host], url: src[:url], holder: src[:holder], licence: src[:licence],
                    licence_url: src[:licence_url], collector: src[:collector] }.compact.presence,
          sci: item[:sci_name], en: name.en, ga: name.ga }
      end
    end

    # Strip a folklore quote's editorial lead-in (see LORE_FRAMES) and re-capitalise what remains,
    # so the words stand as the lore itself; the source is credited separately.
    def strip_lore_framing(text)
      return text if text.blank?

      out = text.to_s
      LORE_FRAMES.each { |frame| out = out.sub(frame, '') }
      out.sub(/\A\p{Ll}/, &:upcase)
    end

    # Each notable bird's source page(s), keyed by sci_name, for the inline citation mark that
    # trails the bullet naming it (TodayCard.emphasised_bullets). Drawn from the bird's current
    # enrichment bundle — the traceable pages behind its FACTS (folklore is excluded: it renders as
    # the set-apart quote with its own dúchas/CC credit, not as a fact citation). One quiet link per
    # distinct host, capped, so the mark stays a footnote, not a wall.
    def citation_map(facts)
      scis = Array(facts[:items]).filter_map { |i| i[:sci_name].presence }.uniq
      EnrichmentBundle.current_for(scis).each_with_object({}) do |bundle, map|
        pages = bundle_citations(bundle)
        map[bundle.sci_name] = pages if pages.any?
      end
    end

    def bundle_citations(bundle)
      bundle.block_objects.
        reject { |b| b.type == 'folklore' }.
        flat_map(&:sources).
        filter_map { |s| s[:url].present? && { label: source_label(s[:host]), url: s[:url], host: s[:host] } }.
        uniq { |page| page[:host] || page[:url] }.
        first(2).
        map { |page| page.slice(:label, :url) }
    end

    def source_label(host)
      HOST_LABEL[host.to_s] || host.to_s.delete_prefix('www.')
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
      { date: nil, date_label: { en: '', ga: '' },
        figures: { species: 0, detections: 0, duration_seconds: nil, busiest: nil },
        heard: [],
        summary: { en: [], ga: [] }, source: nil, sources: [], sparkline: nil, offline: false,
        mic_hours: nil,
        day_lore: nil, place: nil, notable: notable_json(days: 1), quotes: [],
        available: { first: nil, last: Date.yesterday.iso8601 } }
    end
  end
end
