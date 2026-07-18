# The facts engine. All reasoning about a day's detections lives here: counts,
# rankings, the two kinds of "first", local rarity, importance scoring, the 24h
# activity curve and a spotlight pick. It reads the detection store and returns a
# plain Hash — the facts object the summary prompt narrates and the pages render.
#
# Two rules keep the warmth honest:
#   * Ruby computes, the LLM only narrates. Every number and claim is decided here.
#   * Pure and offline. `for` touches only the database. The one lazy network hop
#     (the spotlight's background blurb) is opt-in via `spotlight_blurb:` so a page
#     load never fetches — only the summary refresh does.
class DailyFacts
  # A resident heard daily must never read as an "arrival". A species counts as a
  # seasonal first only if it was absent for this many days before today — closer
  # to what a birder means by "first of the year" than the calendar, and it avoids
  # flagging every resident on 1 January.
  ARRIVAL_WINDOW_DAYS = 30
  # Local rarity is measured against the station's own history: heard on only a
  # handful of the last N days is locally scarce; heard daily is not.
  RARE_WINDOW_DAYS = 200
  RARE_MAX_DAYS = 5
  # Rarity needs a baseline — in the first weeks everything looks rare, so hold the
  # signal until there's enough history for it to mean anything.
  RARE_MIN_AGE_DAYS = 30
  # In the first year every species is an all-time-first, which would flood the
  # "news". Until a full year's baseline exists, damp all-time-firsts so genuine
  # seasonal arrivals lead instead of "NEW!" about a House Sparrow on day two.
  YOUNG_STATION_DAYS = 365
  # Trailing days used for the coarse volume-anomaly / activity-note baselines.
  BASELINE_DAYS = 14
  # The loudest few tallies carry the "most_common" texture flag.
  MOST_COMMON_TOP = 3
  # Wikipedia blurbs fed to the LLM are capped to the most important arrivals — a bound
  # on network hops and on how much the summary tries to characterise in one note.
  MAX_BLURBS = 2
  # Importance is the single integer the summary orders by; flags are metadata.
  NOTABLE_IMPORTANCE = 60
  # Heartbeats prune to ~2 days, so a day older than this can't be assessed for coverage; its
  # coverage is left unknown (nil → drawn as fully covered) rather than falsely painted offline.
  COVERAGE_MAX_AGE_DAYS = 2
  # Share of the elapsed day the recorder must have been up before a pace verdict
  # ("quieter/busier than typical") means anything. Below this the count reflects the gap,
  # not the birds, so DailyFacts makes no claim at all.
  LISTENING_FOR_PACE = 0.9
  IMPORTANCE = {
    all_time_first:       100,
    all_time_first_young: 70,
    year_first:           80,
    rare_local:           60,
    unusual_volume:       40,
    routine:              5
  }.freeze
  # The deterministic template's wording, per language. Irish scaffolding is a first
  # pass — worth a native check — but the counts and names it wraps are exact.
  TEMPLATE_PHRASES = {
    en: { count:    '%<species>s species and %<detections>s detections logged today.',
          firsts:   'New for the station: %<names>s.',
          years:    'First of the year: %<names>s.',
          common:   'Most heard: %<names>s.',
          peak:     'Busiest around %<hour>s.',
          activity: { 'busier_than_typical'  => 'A busier day than usual.',
                      'quieter_than_typical' => 'A quieter day than usual.' } },
    ga: { count:    '%<species>s speiceas agus %<detections>s brath logáilte inniu.',
          firsts:   'Nua ag an stáisiún: %<names>s.',
          years:    'Céaduair i mbliana: %<names>s.',
          common:   'Ba mhó a chualathas: %<names>s.',
          peak:     'Ba ghnóthaí thart ar %<hour>s.',
          activity: { 'busier_than_typical'  => 'Lá níos gnóthaí ná mar is gnách.',
                      'quieter_than_typical' => 'Lá níos ciúine ná mar is gnách.' } }
  }.freeze

  class << self
    # The whole facts object for a day. `spotlight_blurb:` gates the one network
    # hop, so /api/overview (default false) never fetches and the summary refresh
    # (true) does.
    def for(date: Date.current, now: Time.current, spotlight_blurb: false)
      new(date: date, now: now).to_h(spotlight_blurb: spotlight_blurb)
    end

    # Days since the station first heard anything — the "day N of listening" number
    # and the young-station guard. Zero before the first detection.
    def station_age_days(now: Time.current)
      first = Detection.minimum(:Date)
      first ? (now.to_date - first).to_i : 0
    end

    # The deterministic, always-correct fallback: pure Ruby bullets off the facts hash,
    # no model. Plain but honest — used when there is no cached LLM summary. Bilingual
    # (the panel and site both speak one language), returned as { en: [...], ga: [...] }.
    def template_bullets(facts)
      { en: template_lines(facts, :en), ga: template_lines(facts, :ga) }
    end

    private

    def template_lines(facts, lang)
      phrases = TEMPLATE_PHRASES[lang]
      bullets = [format(phrases[:count], species: facts[:species_today], detections: facts[:detections_today])]
      firsts = names_with(facts, 'all_time_first', lang)
      years  = names_with(facts, 'year_first', lang)
      common = common_names(facts, lang)
      bullets << format(phrases[:firsts], names: lead_phrase(firsts, lang)) if firsts.any?
      bullets << format(phrases[:years], names: lead_phrase(years, lang)) if years.any?
      bullets << format(phrases[:common], names: common.join(', ')) if common.any?
      # Texture to round out a quiet day (no arrivals): the day's tempo vs its own baseline,
      # and the busiest hour. Order after the news so firsts still lead; capped at four.
      bullets << phrases[:activity][facts[:activity_note].to_s] if phrases[:activity].key?(facts[:activity_note].to_s)
      peak = peak_hour(facts[:activity_curve_24h])
      bullets << format(phrases[:peak], hour: peak) if peak
      bullets.first(4)
    end

    # The clock-hour with the most detections today (e.g. "08:00"), or nil on a silent day.
    # activity_curve_24h is an array of { hour:, count: } buckets.
    def peak_hour(curve)
      curve = Array(curve)
      return nil if curve.sum { |b| b[:count].to_i }.zero?

      format('%<h>02d:00', h: curve.max_by { |b| b[:count].to_i }[:hour])
    end

    def names_with(facts, flag, lang = :en)
      facts[:items].select { |i| i[:flags].include?(flag) }.map { |i| item_name(i, lang) }
    end

    def common_names(facts, lang)
      facts[:items].select { |i| i[:flags].include?('most_common') }.first(3).map { |i| item_name(i, lang) }
    end

    # The item's name in the chosen language — Irish where we have it, English otherwise.
    def item_name(item, lang)
      lang == :ga ? item[:irish_name].presence || item[:common_name] : item[:common_name]
    end

    # Name the single most important item; collapse the rest to "+N more" so a bullet is
    # never an unbounded comma-list of species (a layout contract).
    def lead_phrase(names, lang = :en)
      return names.first if names.length == 1

      more = lang == :ga ? "agus #{names.length - 1} eile" : "and #{names.length - 1} more"
      "#{names.first}, #{more}"
    end
  end

  attr_reader :date, :now

  def initialize(date: Date.current, now: Time.current)
    @date = date
    @now = now
  end

  def to_h(spotlight_blurb: false)
    list = spotlight_blurb ? items_with_arrival_blurbs : items
    {
      date:               @date.to_s,
      species_today:      today_tally.size,
      detections_today:   detections_today,
      items:              list,
      spotlight:          spotlight(include_blurb: spotlight_blurb),
      activity_note:      activity_note,
      listening:          listening,
      activity_curve_24h: activity_curve_24h,
      coverage_24h:       coverage_24h,
      notable_today:      list.select { |i| i[:importance] >= NOTABLE_IMPORTANCE },
      station_age_days:   station_age_days
    }
  end

  private

  def today_tally
    @today_tally ||= Detection.tally_for(date)
  end

  def detections_today
    @detections_today ||= Detection.on_date(date).count
  end

  def station_age_days
    @station_age_days ||= self.class.station_age_days(now: now)
  end

  def young_station?
    station_age_days < YOUNG_STATION_DAYS
  end

  # First-heard date per species, from the life list (one grouped query).
  def first_seen_dates
    @first_seen_dates ||= Detection.life_list.to_h do |entry|
      [entry.sci_name, parse_date(entry.first_seen)]
    end
  end

  # One scored item per credible species heard today, importance-ranked. The
  # loudest few carry the most_common texture flag.
  def items
    @items ||= today_tally.each_with_index.map { |tally, i| scored_item(tally, most_common: i < MOST_COMMON_TOP) }.
               sort_by { |item| [-item[:importance], -item[:call_count]] }
  end

  # Feed the LLM Wikipedia source text for each flagged arrival, so it narrates the
  # species from fact, not memory. Cached per species by SpeciesInfo — only the day's
  # few arrivals ever hit the network.
  def items_with_arrival_blurbs
    fed = 0
    items.map do |item|
      next item if !item[:flags].intersect?(%w[all_time_first year_first]) || (fed += 1) > MAX_BLURBS

      blurb = SpeciesInfo.english_for(item[:sci_name], item[:common_name])
      blurb.present? ? item.merge(blurb: blurb) : item
    end
  end

  def scored_item(tally, most_common:)
    sci = tally.sci_name
    name = tally.name
    flags = []
    score = IMPORTANCE[:routine]

    if all_time_first?(sci)
      flags << 'all_time_first'
      score = young_station? ? IMPORTANCE[:all_time_first_young] : IMPORTANCE[:all_time_first]
    elsif year_first?(sci)
      flags << 'year_first'
      score = [score, IMPORTANCE[:year_first]].max
    end

    if rare_local?(sci)
      flags << 'rare_local'
      score = [score, IMPORTANCE[:rare_local]].max
    end

    if (volume = volume_anomaly(sci, tally.count))
      # Directional, so the narrator never guesses "above normal" on a species that was
      # in fact unusually QUIET — the flag itself says which way it broke from baseline.
      flags << "unusual_volume_#{volume}"
      score = [score, IMPORTANCE[:unusual_volume]].max
    end

    flags << 'most_common' if most_common
    flags << 'routine' if flags.empty? || flags == ['most_common']

    {
      common_name: name.en, irish_name: name.ga, sci_name: sci,
      call_count: tally.count, importance: score, flags: flags
    }
  end

  # Never heard before today: the species' first-ever record is today.
  def all_time_first?(sci)
    first_seen_dates[sci] == date
  end

  # Heard today but absent for the whole arrival window before today (and not an
  # all-time-first). The seasonal-return signal.
  def year_first?(sci)
    return false if all_time_first?(sci)

    window = (date - ARRIVAL_WINDOW_DAYS)...date
    Detection.where(Sci_Name: sci, Date: window).none?
  end

  # Locally scarce: heard on only a handful of the last RARE_WINDOW_DAYS days.
  # Held until the station has a baseline worth measuring against.
  def rare_local?(sci)
    return false if station_age_days < RARE_MIN_AGE_DAYS

    window = (date - RARE_WINDOW_DAYS)..date
    days_heard = Detection.where(Sci_Name: sci, Date: window).distinct.count(:Date)
    days_heard.positive? && days_heard <= RARE_MAX_DAYS
  end

  # Today's count sits well outside this species' own recent daily average, and WHICH
  # way — :high (more than twice baseline) or :low (less than half), else nil. Coarse
  # and conservative: silent until there's enough history, and only fires on a clear
  # departure from baseline. The direction matters: the summary must not call a quiet
  # day a busy one.
  def volume_anomaly(sci, count_today)
    baseline = species_baseline(sci)
    return nil unless baseline
    return :high if count_today > baseline * 2
    return :low if count_today < baseline * 0.5

    nil
  end

  # Mean daily count on the days this species was heard in the trailing window
  # (excluding today), or nil if too thin to trust.
  def species_baseline(sci)
    window = (date - BASELINE_DAYS)...date
    by_day = Detection.where(Sci_Name: sci, Date: window).group(:Date).count
    return nil if by_day.size < BASELINE_DAYS / 2

    by_day.values.sum.to_f / by_day.size
  end

  # The single species to feature: highest importance, ties broken all_time_first
  # > year_first > rare_local > loudest. The blurb (source material for the LLM) is
  # fetched only when asked, and cached per species by SpeciesInfo.
  def spotlight(include_blurb: false)
    top = items.min_by { |item| [-item[:importance], -tie_rank(item), -item[:call_count]] }
    return nil unless top

    context = rarity_context(top)
    result = { common_name: top[:common_name], irish_name: top[:irish_name], rarity_context: context }
    result[:blurb] = SpeciesInfo.english_for(top[:sci_name], top[:common_name]) if include_blurb
    result
  end

  def tie_rank(item)
    return 3 if item[:flags].include?('all_time_first')
    return 2 if item[:flags].include?('year_first')
    return 1 if item[:flags].include?('rare_local')

    0
  end

  # A factual one-liner about why the spotlight matters — true by construction.
  def rarity_context(item)
    if item[:flags].include?('all_time_first')
      'first record at the station'
    elsif item[:flags].include?('year_first')
      "first record here in over #{ARRIVAL_WINDOW_DAYS} days"
    elsif item[:flags].include?('rare_local')
      "heard on only a handful of the last #{RARE_WINDOW_DAYS} days"
    end
  end

  # Coarse label only — today's pace against a trailing same-time-of-day baseline.
  # The prompt turns the label into a phrase; the model never computes it.
  #
  # Silent when the recorder wasn't listening for the whole stretch. A day with the mic down
  # for hours produces a low count for a reason that has nothing to do with how busy the birds
  # were, and calling that "quieter than typical" states something the data does not support —
  # the station simply wasn't there to hear it. Hours are also not interchangeable (losing the
  # dawn chorus costs far more than losing mid-afternoon), so the gap can't be corrected for by
  # scaling either; the only honest move is to make no pace claim. `listening` carries the
  # coverage itself, so the narration can say what actually happened instead.
  def activity_note
    baseline = daily_baseline
    return nil unless baseline
    return nil unless fully_listening?

    fraction = ((now.hour + 1) / 24.0)
    expected = baseline * fraction
    return nil if expected.zero?

    ratio = detections_today / expected
    return :busier_than_typical if ratio > 1.5
    return :quieter_than_typical if ratio < 0.6

    :typical
  end

  # Was the recorder up for essentially the whole elapsed stretch? Unknown coverage (no ticks
  # at all) counts as yes — that's the pre-heartbeat past, not evidence of a gap.
  def fully_listening?
    cover = listening
    return true if cover.nil?

    cover[:hours_live] >= (cover[:hours_elapsed] * LISTENING_FOR_PACE)
  end

  # How much of the day the mic → BirdNET loop was actually up: hours live out of hours
  # elapsed. The stat every count on the page has to be read against — a low species count
  # means one thing after a full day's listening and quite another after four hours of it.
  # A heartbeat tick OR a detection proves an hour was live (same test as coverage_24h).
  # nil when the station has never ticked, so a gap can't be told from an unmonitored past.
  def listening
    return @listening if defined?(@listening)

    @listening = compute_listening
  end

  def compute_listening
    return nil unless Heartbeat.exists?

    elapsed = @date >= Date.current ? now.hour + 1 : 24
    alive = Heartbeat.coverage(@date.in_time_zone.beginning_of_day, 3600, elapsed)
    counts = activity_curve_24h
    live = Array.new(elapsed) { |i| alive[i] || counts[i][:count].to_i.positive? }.count(true)
    { hours_live: live, hours_elapsed: elapsed }
  end

  # Mean total detections per day over the trailing window (excluding today), or
  # nil if there aren't enough days to mean anything.
  def daily_baseline
    window = (date - BASELINE_DAYS)...date
    by_day = Detection.where(Date: window).group(:Date).count
    return nil if by_day.size < BASELINE_DAYS / 2

    by_day.values.sum.to_f / by_day.size
  end

  # Detections bucketed into 24 hours — the data behind the home page sparkline.
  # Uses raw detections (matching detections_today), DB-agnostic via the Time cast.
  def activity_curve_24h
    counts = Array.new(24, 0)
    Detection.on_date(date).pluck(:Time).each do |value|
      hour = hour_of(value)
      counts[hour] += 1 if hour
    end
    counts.each_index.map { |hour| { hour: hour, count: counts[hour] } }
  end

  # Was the mic → BirdNET loop up each hour of a COMPLETED day — 24 booleans — so the Journal can
  # tell an offline stretch from a genuinely quiet one. A heartbeat tick OR a detection proves the
  # hour was live. nil (unknown, drawn as fully covered) when: the day isn't finished yet; it's
  # older than heartbeats are kept (they prune to ~2 days), so we can't assess it; or the station
  # has never sent a tick. Computed at freeze time (00:15, ticks still fresh) and stored on the
  # entry — never recomputed on a later read, when the ticks would be gone.
  def coverage_24h
    return nil if @date >= Date.current || @date < Date.current - COVERAGE_MAX_AGE_DAYS
    return nil unless Heartbeat.exists?

    alive = Heartbeat.coverage(@date.in_time_zone.beginning_of_day, 3600, 24)
    counts = activity_curve_24h
    Array.new(24) { |i| alive[i] || counts[i][:count].positive? }
  end

  def hour_of(value)
    return nil unless value
    return value.hour if value.respond_to?(:hour)

    Time.zone.parse(value.to_s)&.hour
  end

  def parse_date(value)
    return value if value.is_a?(Date)

    Date.parse(value.to_s[0, 10])
  rescue ArgumentError, TypeError
    nil
  end
end
