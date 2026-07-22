# The RICH layer of the calendar (day_lore.yml): the custom, belief, legend or tale hand-curated
# for a particular day. Highest precedence in the day-section after the Féilire NAME — it's what
# the Journal shows when the day carries genuine curated lore, above the felire_lore floor (see
# CLAUDE.md §3). Sparse by design: most days have none, and fall through to that floor.
#
# This service resolves the DATED lore: an MM-DD entry, or a movable feast whose date is computed
# from Easter. The seasonal (season:*) entries are a separate, thin-day/weather fallback handled
# alongside place_lore, not here.
class DayLore
  # Movable feasts keyed `movable:<name>`, as a day-offset from Easter Sunday.
  MOVABLE_OFFSETS = { 'whitsuntide' => 49 }.freeze # Whit Sunday (Pentecost) = Easter + 49 days

  class << self
    # The featured day-lore for a date as a display hash, or nil when the day has no dated entry.
    def for(date)
      entry = dated(date) || movable(date)
      entry && display(entry)
    end

    # Easter Sunday for a Gregorian year (the Anonymous Gregorian computus). Public so the movable
    # feasts are testable and any other layer can reuse it.
    def easter(year)
      a = year % 19
      b, c = year.divmod(100)
      d, e = b.divmod(4)
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = (((19 * a) + b - d - g + 15) % 30)
      i, k = c.divmod(4)
      l = (32 + (2 * e) + (2 * i) - h - k) % 7
      m = (a + (11 * h) + (22 * l)) / 451
      day = ((h + l - (7 * m) + 114) % 31) + 1
      Date.new(year, (h + l - (7 * m) + 114) / 31, day)
    end

    private

    def data
      StationProfile.yaml('content/day_lore.yml')
    end

    def dated(date)
      first(data[date.strftime('%m-%d')])
    end

    # A movable feast falls on this date when the date matches Easter + its offset for the year.
    def movable(date)
      MOVABLE_OFFSETS.each do |name, offset|
        return first(data["movable:#{name}"]) if date == easter(date.year) + offset
      end
      nil
    end

    # A day key holds a LIST of entries (featured first); a lone hash is tolerated.
    def first(raw)
      raw.is_a?(Array) ? raw.first : raw
    end

    # The featured entry → the Journal display shape: its kind, title, prose and/or a set-apart
    # verse/charm, a context note, and a composed source credit.
    def display(entry)
      return nil unless entry.is_a?(Hash)

      {
        kind:   entry['kind'].to_s.strip.presence,
        title:  entry['title'].to_s.strip.presence,
        text:   entry['text'].to_s.strip.presence,
        quote:  entry['quote'].to_s.strip.presence,
        note:   entry['note'].to_s.strip.presence,
        credit: credit_for(entry)
      }
    end

    # "Collected by Lady Wilde · Ancient Legends… (1887)" — attribution, then the source work and
    # year. Every entry carries these (the discipline: nothing displays without provenance).
    def credit_for(entry)
      attribution = entry['attribution'].to_s.strip.presence
      work = entry['source_work'].to_s.strip.presence
      year = entry['year']
      book = if work then year ? "#{work} (#{year})" : work
             elsif year then year.to_s
             end
      [attribution, book].compact.join(' · ').presence
    end
  end
end
