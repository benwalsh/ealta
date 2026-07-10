require 'erb'
require 'cgi'

# The whole "TODAY" card, computed in Ruby so the view only iterates and prints
# (Ruby computes, the view renders). It assembles the daily voice (2-4 capped
# bullets), the past-24h sparkline as ready SVG paths, its time anchors, the
# right-aligned total, and the ambient footer readings. Everything bilingual, so
# the client picks a language without another round-trip.
class TodayCard
  # Irish day/month names for the header date (Ruby has no ga locale for these).
  GA_DAYS = %w[Domhnach Luan Máirt Céadaoin Déardaoin Aoine Satharn].freeze
  GA_MONTHS = [nil, 'Eanáir', 'Feabhra', 'Márta', 'Aibreán', 'Bealtaine', 'Meitheamh',
               'Iúil', 'Lúnasa', 'Meán Fómhair', 'Deireadh Fómhair', 'Samhain', 'Nollaig'].freeze
  # English weather word -> Tabler icon. Unmatched weather falls back to a cloud.
  WEATHER_ICONS = {
    'clear' => 'ti-sun', 'fair' => 'ti-sun', 'cloudy' => 'ti-cloud', 'overcast' => 'ti-cloud',
    'fog' => 'ti-fog', 'drizzle' => 'ti-cloud-drizzle', 'rain' => 'ti-cloud-rain',
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

    # Turn each blind-spot band's bucket range into clock-time labels: a full
    # "No data · 06:00–08:48" and a compact "No data · 3h" the phone view uses. Bilingual.
    def gap_labels(gaps, now, start)
      bucket = (now - start) / BUCKETS
      Array(gaps).map do |g|
        from = start + (g[:from] * bucket)
        to   = start + ((g[:to] + 1) * bucket)
        span = "#{from.strftime('%H:%M')}–#{to.strftime('%H:%M')}"
        dur  = duration_label(to - from)
        { x0: g[:x0], x1: g[:x1],
          label: { en: "No data · #{span}", ga: "Gan sonraí · #{span}" },
          short: { en: "No data · #{dur}", ga: "Gan sonraí · #{dur}" } }
      end
    end

    # A compact duration: whole hours once past an hour, otherwise minutes.
    def duration_label(seconds)
      seconds >= 3600 ? "#{(seconds / 3600.0).round}h" : "#{(seconds / 60.0).round}m"
    end

    # Just the ambient almanac readings (weather / moon / sun / tide / place), the same
    # bilingual line-icon items the home page's row renders — no sparkline, no LLM
    # narration. The station panel reads this so its footer is a subset of the home
    # page's content, not a parallel one of its own.
    def almanac(now: Time.current)
      footer_items(now)
    end

    # A bilingual "Wednesday, 8 July" label for a day. Public — the Journal reuses it for a
    # completed date (pass that date as a Time).
    def date_label(now)
      { en: now.strftime('%A, %-d %B'),
        ga: "#{GA_DAYS[now.wday]}, #{now.day} #{GA_MONTHS[now.month]}" }
    end

    # Bullets with species names emphasised, HTML-escaped, capped at four. English common
    # names go weight-500 (<strong>); Irish names take the serif voice-italic. `kind` is the
    # bullet's own language. Names are found two ways so this holds up whatever case or
    # inflection the model uses: the model wraps each name in **double asterisks**, and as a
    # fallback we also match the canonical English/Irish names case-insensitively.
    def emphasised_bullets(bullets, facts, kind)
      items = Array(facts[:items])
      en_names = items.filter_map { |i| i[:common_name].presence }.uniq
      ga_names = items.filter_map { |i| i[:irish_name].presence }.uniq
      sci_of = name_sci_map(items)
      Array(bullets).first(4).map { |bullet| emphasise(bullet, en_names, ga_names, sci_of, kind) }
    end

    private

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
    def emphasise(text, en_names, ga_names, sci_of, kind)
      safe = ERB::Util.html_escape(text)
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
      swapped = safe.gsub(/#{Regexp.escape(MARK)}(\d+)#{Regexp.escape(MARK)}/o) do
        name, name_kind = slots[::Regexp.last_match(1).to_i]
        tag_for(name, name_kind, kind, sci_of)
      end
      swapped.gsub('**', '') # drop any stray unpaired marker so it never renders literally
    end

    # The naming convention: the PRIMARY name (the one matching the bullet's own language) is
    # bold and links to its card (data-sci); the SECONDARY name (the other language, which the
    # narration puts in parentheses) is plain. `bullet_kind` is the bullet's language, `kind`
    # the matched name's. Text is already HTML-escaped here.
    def tag_for(name, kind, bullet_kind, sci_of)
      return name unless kind == bullet_kind # secondary-language name → plain, in its parens

      sci = sci_of[CGI.unescapeHTML(name).downcase]
      attr = sci ? %( data-sci="#{ERB::Util.html_escape(sci)}") : ''
      %(<strong class="bird"#{attr}>#{name}</strong>)
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
    # detection landed. With no ticks in the window at all — the cloud mirror, or before
    # the mic is installed — we can't claim any blind spots, so treat it as fully covered
    # (the sparkline then draws exactly as it always did).
    def coverage(start, width, buckets)
      alive = Heartbeat.coverage(start, width, buckets.length)
      return Array.new(buckets.length, true) unless alive.any?

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
      items << { icon: 'ti-moon', en: "#{moon.illumination}% #{moon.name.downcase}",
                 ga: "#{moon.illumination}% #{moon.name_ga.downcase}" }
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
        en: "#{weather[:temp]}°C #{weather[:text]}", ga: "#{weather[:temp]}°C #{weather[:text_ga]}" }
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
