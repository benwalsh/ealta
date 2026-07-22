require 'erb'
require 'cgi'

# The whole "TODAY" card, computed in Ruby so the view only iterates and prints
# (Ruby computes, the view renders). It assembles the daily voice (2-4 capped
# bullets), the past-24h sparkline as ready SVG paths, its time anchors, the
# right-aligned total, and the ambient footer readings. Everything bilingual, so
# the client picks a language without another round-trip.
class TodayCard
  # Irish day/month names for the header date (Ruby has no ga locale for these). The weekdays
  # carry their "Dé" particle in the proper inflected forms the dateline shows — "Dé Luain",
  # "Dé hAoine", "Déardaoin" (Thursday takes no particle) — not the bare nominatives, so
  # naive "Dé " prefixing (which would give "Dé Aoine"/"Dé Satharn") is avoided. Indexed by wday.
  GA_DAYS = ['Dé Domhnaigh', 'Dé Luain', 'Dé Máirt', 'Dé Céadaoin', 'Déardaoin',
             'Dé hAoine', 'Dé Sathairn'].freeze
  GA_MONTHS = [nil, 'Eanáir', 'Feabhra', 'Márta', 'Aibreán', 'Bealtaine', 'Meitheamh',
               'Iúil', 'Lúnasa', 'Meán Fómhair', 'Deireadh Fómhair', 'Samhain', 'Nollaig'].freeze
  # English weather word -> Tabler icon. Unmatched weather falls back to a cloud.
  # NB: fog and drizzle formerly pointed at icon names absent from Tabler 3.44.0, so both
  # rendered as a blank tofu square. Now real glyphs: cloud-fog (same family as the others) and
  # droplets (distinct from the rain cloud that rain/showers use). Every value here must be a
  # real class — the icon-subset build only ships glyphs it can find referenced.
  WEATHER_ICONS = {
    'clear' => 'ti-sun', 'fair' => 'ti-sun', 'cloudy' => 'ti-cloud', 'overcast' => 'ti-cloud',
    'fog' => 'ti-cloud-fog', 'drizzle' => 'ti-droplets', 'rain' => 'ti-cloud-rain',
    'showers' => 'ti-cloud-rain', 'snow' => 'ti-snowflake', 'thunderstorm' => 'ti-bolt'
  }.freeze
  # Null-delimited placeholder used while wrapping names — cannot occur in the text.
  MARK = "\u0000".freeze

  # The sparkline is always this many buckets wide, whatever the span — a fixed
  # resolution keeps the line's texture consistent as the window changes.
  BUCKETS = 24
  # Windows at/above this are the "all time" sentinel (ApplicationController::WINDOWS
  # uses 1_000_000); the line then spans from the first-ever detection.
  ALL_THRESHOLD = 100_000

  class << self
    # window_hours sets the sparkline's span — the trailing window the graph covers
    # (default 24h). The narrative (date, bullets) always stays about today; only the
    # activity line rescales.
    def build(now: Time.current, window_hours: 24)
      facts = DailyFacts.for(now: now)
      summary = TodaySummary.current(facts: facts)
      counts, total, start, coverage = series(now, window_hours)
      spark = Sparkline.paths(counts, coverage: coverage)
      {
        date_label: date_label(now),
        summary:    { en: emphasised_bullets(summary[:bullets][:en], facts, :en),
                      ga: emphasised_bullets(summary[:bullets][:ga], facts, :ga) },
        source:     summary[:source],
        sources:    Array(summary[:sources]).map { |s| { host: s[:host], url: s[:url] } },
        total:      total,
        sparkline:  { path: spark.path, fill: spark.fill,
                      gaps: gap_labels(spark.gaps, now, start), w: spark.w, h: spark.h },
        anchors:    anchors(now, start),
        footer:     footer_items(now, place: false)
      }
    end

    # The blind-spot bands, as x-spans the view can use. No labels: the sparkline shows a gap
    # by breaking (or by drawing nothing at all when the whole window is uncovered), so there
    # is no longer a slab to caption. `offline` / `mic_hours` carry the same fact in words.
    def gap_labels(gaps, _now, _start)
      Array(gaps).map { |g| { x0: g[:x0], x1: g[:x1] } }
    end

    # Just the ambient almanac readings (weather / moon / sun / tide / place), the same
    # bilingual line-icon items the home page's row renders — no sparkline, no LLM
    # narration. The station panel reads this so its footer is a subset of the home
    # page's content, not a parallel one of its own.
    def almanac(now: Time.current)
      footer_items(now)
    end

    # A bilingual "Wednesday, 8 July 2026" label for a day. Public — the Journal reuses it for a
    # completed date (pass that date as a Time). The year is carried so a diary entry read out of
    # season still says which year it belongs to.
    def date_label(now)
      { en: now.strftime('%A, %-d %B, %Y'),
        ga: "#{GA_DAYS[now.wday]}, #{now.day} #{GA_MONTHS[now.month]}, #{now.year}" }
    end

    # The compact date for the panel's printed stamp — day and month, no weekday. A time alone
    # can't tell you whether the impression is an hour old or a week old; the date can, and it
    # is the only way a stopped station gives itself away on the wall.
    def stamp_date(now)
      { en: now.strftime('%-d %B'), ga: "#{now.day} #{GA_MONTHS[now.month]}" }
    end

    # The seconds the recorder was actually LISTENING across the window (the mic → BirdNET loop
    # up), i.e. the span minus its blind spots — so the stats block's "duration" reads as coverage,
    # not wall-clock: "the time the station wasn't listening" is already taken out. Derived from the
    # same per-bucket coverage the sparkline draws. nil for the "all time" span (a lifetime figure
    # is not a listening duration). When no heartbeats exist at all, coverage is wholly true (we
    # can't claim blind spots we can't see), so this returns the full span.
    def listening_seconds(now: Time.current, window_hours: 24)
      return nil if window_hours >= ALL_THRESHOLD

      _counts, _total, start, coverage = series(now, window_hours)
      width = (now - start) / BUCKETS
      return 0 if width <= 0

      (coverage.count { |up| up } * width).round
    end

    # Bullets with species names emphasised, HTML-escaped, capped at four. The PRIMARY name (the
    # bullet's own language) goes weight-500 (<strong>) and links to its card; the SECONDARY name
    # (the other language) follows in parentheses, voice-italic. Every prominently-named bird reads
    # the same — "Primary (secondary)" — whether or not the model wrote the second name: where the
    # prose already carries it we just style it, and where it doesn't we add the canonical one, once
    # per bird per entry. `kind` is the bullet's own language. Names are found two ways so this holds
    # up whatever case or inflection the model uses: the model wraps each name in **double
    # asterisks**, and as a fallback we also match the canonical English/Irish names.
    #
    # `cites` (sci_name => [{ label:, url: }]) attaches each bird's source citation INLINE, as a
    # muted mark at the end of the bullet it appears in — the traceable page behind that bird's
    # facts, next to the bird rather than lumped at the foot of the entry. Empty (the default, e.g.
    # the e-ink panel) leaves the bullets citation-free, exactly as before.
    def emphasised_bullets(bullets, facts, kind, cites: {})
      items = Array(facts[:items])
      en_names = items.filter_map { |i| i[:common_name].presence }.uniq
      ga_names = items.filter_map { |i| i[:irish_name].presence }.uniq
      sci_of = name_sci_map(items)
      sec_of = secondary_map(items, kind)
      glossed = {} # sci => true once its second name has been added — first mention only, entry-wide
      Array(bullets).first(4).map do |bullet|
        emphasise(bullet, en_names, ga_names, sci_of, sec_of, glossed, kind, cites)
      end
    end

    private

    # sci_name => the OTHER-language name a primary mention is glossed with (the Irish name for an
    # English bullet, the English name for an Irish one). Only where a DISTINCT second name exists,
    # so a single-language station (where ga mirrors en) never glosses a name with itself. Irish
    # glosses are lowered to the running-prose form the names take mid-sentence ("snag breac", not
    # "Snag breac"); the English gloss keeps its title case.
    def secondary_map(items, kind)
      items.each_with_object({}) do |item, map|
        primary   = kind == :ga ? item[:irish_name] : item[:common_name]
        secondary = kind == :ga ? item[:common_name] : item[:irish_name]
        next if item[:sci_name].blank? || secondary.blank? || primary.to_s.casecmp?(secondary.to_s)

        map[item[:sci_name]] = kind == :ga ? secondary : secondary.downcase
      end
    end

    # Downcased common/Irish name → sci_name, so an emphasised name can carry a data-sci and
    # link to its card.
    def name_sci_map(items)
      items.each_with_object({}) do |item, map|
        map[item[:common_name].to_s.downcase] = item[:sci_name] if item[:common_name].present?
        map[item[:irish_name].to_s.downcase] = item[:sci_name] if item[:irish_name].present?
      end
    end

    # Locate names, stamp each as a null-delimited placeholder (so one can't be wrapped
    # inside another), then swap the placeholders for tags. A **marked** name is Irish when
    # it matches a canonical Irish name or the bullet itself is Irish, else English; the
    # canonical fallback tags by which list matched. The wrapped text keeps the model's own
    # spelling/case, not the canonical form.
    def emphasise(text, en_names, ga_names, sci_of, sec_of, glossed, kind, cites = {})
      safe = ERB::Util.html_escape(text)
      text_lc = text.to_s.downcase # to tell whether the prose already carries a bird's second name
      # Collapse a redundant "**X** (X)" — the Irish translation sometimes repeats the same
      # name in the parenthetical (there being no distinct second name); keep it once. The
      # parenthetical may or may not carry its own ** markers.
      safe = safe.gsub(/\*\*([^*]+?)\*\*\s*\(\**\1\**\)/i, '**\1**')
      slots = []
      stamp = ->(str, tag_kind) {
        slots << [str, tag_kind]
        "#{MARK}#{slots.size - 1}#{MARK}"
      }

      safe = safe.gsub(/\*\*(.+?)\*\*/) do
        name = ::Regexp.last_match(1)
        irish = kind == :ga || ga_names.any? { |n| ERB::Util.html_escape(n).casecmp?(name) }
        stamp.call(name, irish ? :ga : :en)
      end
      (ga_names.map { |n| [n, :ga] } + en_names.map { |n| [n, :en] }).sort_by { |n, _| -n.length }.each do |name, k|
        safe = safe.gsub(/#{Regexp.escape(ERB::Util.html_escape(name))}/i) { |match| stamp.call(match, k) }
      end
      # Which birds this bullet names (by their PRIMARY, card-linked mention) — the set whose
      # citations trail the bullet, in first-mention order.
      seen = []
      swapped = safe.gsub(/#{Regexp.escape(MARK)}(\d+)#{Regexp.escape(MARK)}/o) do
        name, name_kind = slots[::Regexp.last_match(1).to_i]
        html, sci = tag_for(name, name_kind, kind, sci_of, sec_of, glossed, text_lc)
        seen << sci if sci
        html
      end
      swapped = swapped.gsub('**', '') # drop any stray unpaired marker so it never renders literally
      swapped + citation_tail(seen, cites)
    end

    # The naming convention: the PRIMARY name (the one matching the bullet's own language) is
    # bold and links to its card (data-sci), followed by its SECONDARY name (the other language)
    # in italic parens; the secondary is either the one the narration already wrote (matched
    # separately, styled here) or — when the prose gave none — the canonical one added by `gloss`.
    # `bullet_kind` is the bullet's language, `kind` the matched name's. Returns [html, sci] — sci
    # is the card key when this was the primary mention, nil for a bare italic secondary already in
    # the prose. Text is already HTML-escaped here.
    def tag_for(name, kind, bullet_kind, sci_of, sec_of, glossed, text_lc)
      return [%(<em class="bird-alt">#{name}</em>), nil] unless kind == bullet_kind

      sci = sci_of[CGI.unescapeHTML(name).downcase]
      attr = sci ? %( data-sci="#{ERB::Util.html_escape(sci)}") : ''
      ["<strong class=\"bird\"#{attr}>#{name}</strong>#{gloss(sci, sec_of, glossed, text_lc)}", sci]
    end

    # The second-language name in italic parens after a primary mention — added the FIRST time a
    # bird is named in the entry, and only when the prose doesn't already carry that name, so every
    # prominently-named bird reads "Primary (secondary)" whether or not the narration wrote it.
    def gloss(sci, sec_of, glossed, text_lc)
      return '' unless sci

      secondary = sec_of[sci]
      return '' if secondary.blank? || glossed[sci] || text_lc.include?(secondary.downcase)

      glossed[sci] = true
      %( (<em class="bird-alt">#{ERB::Util.html_escape(secondary)}</em>))
    end

    # The muted citation mark that trails a bullet: one link per distinct source page behind the
    # birds it names (deduped by URL, in first-mention order), so a fact is traceable next to the
    # bird it belongs to rather than in a lump at the foot of the entry. Empty when the bullet
    # names no cited bird (or `cites` is empty — the panel path).
    def citation_tail(scis, cites)
      return '' if cites.blank?

      pages = scis.uniq.flat_map { |sci| Array(cites[sci]) }.uniq { |c| c[:url] }
      return '' if pages.empty?

      links = pages.map do |c|
        %(<a class="bullet-cite" href="#{ERB::Util.html_escape(c[:url])}" ) +
          %(target="_blank" rel="noopener noreferrer">#{ERB::Util.html_escape(c[:label])}</a>)
      end
      %( <span class="bullet-cites">#{links.join(' ')}</span>)
    end

    # Detections bucketed across the chosen span (oldest-first), the total in that
    # span, and the span's start. BUCKETS slots of equal width, so the same line
    # shape works for an hour or a year.
    def series(now, window_hours)
      start = window_start(now, window_hours)
      width = (now - start) / BUCKETS
      width = 1.0 if width <= 0 # degenerate span (no data yet) — avoid /0
      buckets = Array.new(BUCKETS, 0)
      rows = Detection.since(start).pluck(:Date, :Time)
      rows.each do |date, time|
        moment = combine(date, time)
        next unless moment

        idx = ((moment - start) / width).floor
        idx = BUCKETS - 1 if idx == BUCKETS # the exact 'now' edge lands in the last slot
        buckets[idx] += 1 if idx.between?(0, BUCKETS - 1)
      end
      [buckets, rows.length, start, coverage(start, width, buckets)]
    end

    # Which buckets were OPERATIVE: the listener ticked in them, or (equivalently) a
    # detection landed. When NO heartbeats exist AT ALL — the cloud mirror, or before the mic
    # is installed — we can't claim any blind spots, so treat every bucket as covered (the
    # sparkline draws exactly as it always did). But once heartbeats ARE recorded, gate on
    # whether they exist globally, not just in this window: a window with none of them (and no
    # detections) is a genuine blind spot — "no data" in every timeframe — rather than a quiet
    # resting line in a 12h view and a gap band in the 24h that overlaps it.
    def coverage(start, width, buckets)
      return Array.new(buckets.length, true) unless Heartbeat.exists?

      alive = Heartbeat.coverage(start, width, buckets.length)
      buckets.each_index.map { |i| alive[i] || buckets[i].positive? }
    end

    # The span's start: a fixed window back from now, or — for the "all time"
    # sentinel — the first-ever detection so the line covers the whole record.
    # Falls back to 24h when there's nothing recorded yet.
    def window_start(now, window_hours)
      return now - window_hours.hours if window_hours < ALL_THRESHOLD

      earliest = Detection.minimum(:Date)
      earliest ? Time.zone.local(earliest.year, earliest.month, earliest.day) : now - 24.hours
    end

    def combine(date, time)
      return nil unless date && time

      Time.zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
    rescue ArgumentError
      nil
    end

    # Four evenly-spaced ticks across the span — a true sparkline's minimal axis.
    # Short spans read as clock times (same in both languages); multi-day spans read
    # as dates, with the Irish month for the ga label.
    def anchors(now, start)
      span_hours = (now - start) / 3600.0
      (0..3).map do |i|
        tick = start + ((now - start) * (i / 3.0))
        { x: (i / 3.0).round(4) }.merge(anchor_label(tick, span_hours))
      end
    end

    def anchor_label(tick, span_hours)
      if span_hours <= 48
        clock = tick.strftime('%H:%M')
        { en: clock, ga: clock }
      else
        { en: tick.strftime('%-d %b'), ga: "#{tick.day} #{GA_MONTHS[tick.month]}" }
      end
    end

    # The ambient readings - muted line-icon + short label pairs (never emoji).
    # place: the web almanac row drops it (the page footer carries place + coords instead);
    # the e-ink panel (TodayCard.almanac) keeps it, since the panel has no separate footer.
    def footer_items(now, place: true)
      data = Almanac.current
      moon = MoonPhase.for(now.to_date)
      items = []
      items << weather_item(data[:weather]) if data[:weather]
      # The moon carries its own drawn shape (tonight's real phase) rather than a fixed ti-moon
      # glyph, which is a crescent on every night of the month. `svg` is the SHADOW — the unlit
      # part — because ink reads as dark: inking the lit part instead draws a negative. The view
      # strokes the disc outline over it, so a full moon reads as an open circle.
      # `short` is the panel's form: 480px of e-ink has room for a figure, not a phrase, and
      # the drawn glyph already says which phase it is. The web row keeps the full label.
      items << { icon: 'ti-moon', svg: moon.shadow,
                 en: "#{moon.illumination}% #{moon.name.downcase}",
                 ga: "#{moon.illumination}% #{moon.name_ga.downcase}",
                 short: { en: "#{moon.illumination}%", ga: "#{moon.illumination}%" } }
      if (sun = data[:sun])
        items << { icon: 'ti-sunrise', en: sun[:rise], ga: sun[:rise] }
        items << { icon: 'ti-sunset', en: sun[:set], ga: sun[:set] }
      end
      items << { icon: 'ti-ripple', en: data[:tide][:label], ga: data[:tide][:label_ga] } if data[:tide]
      items << place_item(data) if place
      items
    end

    def weather_item(weather)
      { icon: WEATHER_ICONS.fetch(weather[:text], 'ti-cloud'),
        en: "#{weather[:temp]}°C #{weather[:text]}", ga: "#{weather[:temp]}°C #{weather[:text_ga]}",
        # The panel takes the temperature alone; the icon already carries the conditions.
        short: { en: "#{weather[:temp]}°C", ga: "#{weather[:temp]}°C" } }
    end

    def place_item(data)
      coords = data[:coords] || {}
      place = coords[:place]
      place = { en: place, ga: place } if place.is_a?(String)
      place ||= {}
      en = place[:en] || ENV.fetch('BIRD_PLACE', 'the station')
      { icon: 'ti-map-pin', en: en, ga: place[:ga] || en }
    end
  end
end
