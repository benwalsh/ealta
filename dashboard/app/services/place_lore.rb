# The local-colour layer (place_lore.yml): legends, tales and descriptions fixed to the townlands
# and ground around the station. A rotating piece surfaces in the Journal so every day carries a
# bit of the station's own ground — and, above all, so a stormy winter day that logs no birds still has
# something to say (the coast-wide weather-and-sea and wreck passages are exactly that carry).
#
# The `zone` contract is the guard against drift: the static rotation NEVER reaches past `core`
# (the station's own townland, river, mountain, fjord, and the coast-wide passages). near / wider /
# distant places exist for the dúchas layer's "say where it is" framing, not for this rotation —
# a Journal that keeps talking about places 35 km away stops being local (CLAUDE.md §4).
class PlaceLore
  STATIC_ZONE = 'core'.freeze

  class << self
    # A local-colour story for a date, as a display hash, or nil when the station ships no core
    # place-lore. Rotates deterministically by the day so it's stable for any given date yet varies
    # day to day; unrelated to the birds, so it reads as the coast's own standing character.
    def for(date)
      pool = core_entries
      return nil if pool.empty?

      place, entry = pool[date.jd % pool.size]
      display(place, entry)
    end

    private

    def data
      StationProfile.yaml('content/place_lore.yml')
    end

    # Every core-zone entry as [place_name, entry] pairs, in file order.
    def core_entries
      data.each_with_object([]) do |(name, place), pool|
        next unless place.is_a?(Hash) && place['zone'] == STATIC_ZONE

        Array(place['entries']).each { |entry| pool << [name, entry] if entry.is_a?(Hash) }
      end
    end

    def display(place, entry)
      {
        # The heading drops any disambiguating parenthetical ("This Coast (weather and sea)" →
        # "This Coast") — the story itself supplies the rest.
        place:    place.to_s.sub(/\s*\([^)]*\)/, '').strip,
        kind:     entry['kind'].to_s.strip.presence,
        title:    entry['title'].to_s.strip.presence,
        text:     entry['text'].to_s.strip.presence,
        quote:    entry['quote'].to_s.strip.presence,
        narrator: entry['narrator'].to_s.strip.presence,
        note:     entry['note'].to_s.strip.presence,
        credit:   credit_for(entry)
      }
    end

    # "Roderic O'Flaherty · A Chorographical Description… (1846)" — attribution, then the source
    # work and year. Every entry carries provenance (nothing displays without it).
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
