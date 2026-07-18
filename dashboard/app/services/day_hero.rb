# The day's ONE hero — the bird the Journal and the letter feature (the picture, the deep dive,
# the closing folklore quote). Importance-first, but with a MEMORY: a genuine rarity or first is
# the day's real news and always leads immediately, while an everyday bird that led recently steps
# aside so the common birds stay fresh — the house sparrow surfaces a few times a year, not every
# quiet day it happens to be loudest. The pick is frozen onto the JournalEntry (hero_sci_name), so
# the letter, the web coda and any later re-open all feature the SAME bird, and so this history is
# what "led recently" reads from.
class DayHero
  # A bird at or above this importance (a first, a year-first, a local rarity — see
  # DailyFacts::IMPORTANCE) is genuine news: it always leads, however recently it featured.
  RARITY_FLOOR = 60
  # How long an everyday (sub-rarity) hero rests before it can lead again. Station/env-tunable.
  DEFAULT_COOLDOWN_DAYS = 90

  class << self
    # The hero item (one of `items`, the DailyFacts scored-item hashes) for `as_of`, or nil on a
    # birdless day. Recency is read from the prior frozen entries, never including `as_of` itself.
    def pick(items, as_of:)
      items = Array(items)
      return nil if items.empty?

      rarities = items.select { |i| i[:importance].to_i >= RARITY_FLOOR }
      return top(rarities) if rarities.any? # a rarity always leads, never rested

      recent = recently_featured(as_of)
      fresh = items.reject { |i| recent.include?(i[:sci_name]) }
      # Among everyday birds, prefer one that hasn't led lately; if every candidate has, fall back
      # to plain importance so a bird still leads (a small station with one regular visitor).
      top(fresh.presence || items)
    end

    private

    # Highest importance, loudest breaking ties — matching how DailyFacts already orders items.
    def top(items)
      items.max_by { |i| [i[:importance].to_i, i[:call_count].to_i] }
    end

    # The scientific names that led on a day within the cooldown window before `as_of`.
    def recently_featured(as_of)
      window = JournalEntry.where.not(hero_sci_name: nil).where(date: (as_of - cooldown_days)...as_of)
      window.pluck(:hero_sci_name).to_set
    end

    def cooldown_days
      setting = Station.setting('journal.hero_cooldown_days', env:     'HERO_COOLDOWN_DAYS',
                                                              default: DEFAULT_COOLDOWN_DAYS)
      Integer(setting)
    end
  end
end
