# The day's local character: a curated feast/quarter-day if the date carries one (the station's
# own content/feilire.yml — facts only, never the model), else the Celtic season it falls in, so
# every day has an honest line. `for` returns a bilingual { title:, gloss:, kind: } hash.
# (dúchas-sourced seasonal customs are a later enhancement; this is the reference-supplies-the-
# fact floor.)
class Feilire
  # Celtic seasons begin at the cross-quarter days (Feb/May/Aug/Nov), not the solstices.
  SEASONS = {
    earrach:    { months: [2, 3, 4],   title: { en: 'Spring', ga: 'Earrach' },
                  gloss: { en: 'the growing half of the Irish year', ga: 'leath fáis na bliana' } },
    samhradh:   { months: [5, 6, 7],   title: { en: 'Summer', ga: 'Samhradh' },
                  gloss: { en: 'the height of the Irish year', ga: 'buaic na bliana' } },
    fomhar:     { months: [8, 9, 10],  title: { en: 'Autumn', ga: 'Fómhar' },
                  gloss: { en: 'the harvest half of the year', ga: 'leath an fhómhair' } },
    geimhreadh: { months: [11, 12, 1], title: { en: 'Winter', ga: 'Geimhreadh' },
                  gloss: { en: 'the dark, resting half of the year', ga: 'leath dhorcha na bliana' } }
  }.freeze

  class << self
    # The curated entry for the date, or the Celtic-season fallback. Always returns a hash with
    # string-keyed { 'title' => {...}, 'gloss' => {...}, 'kind' => ... } (matching the YAML).
    def for(date)
      entries[date.strftime('%m-%d')] || season_entry(date)
    end

    private

    def entries
      StationProfile.yaml('content/feilire.yml')
    end

    def season_entry(date)
      key, season = SEASONS.find { |_, s| s[:months].include?(date.month) }
      {
        'title'  => stringify(season[:title]),
        'gloss'  => stringify(season[:gloss]),
        'kind'   => 'season',
        'season' => key.to_s
      }
    end

    def stringify(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
