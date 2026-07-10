require 'json'

# Bilingual name lookup, keyed by BirdNET scientific name.
#
# English is always the base; the SECOND-language name is the first non-English language the
# station offers (Station.languages, from station.yml), read from the matching stock BirdNET
# locale file at model/l18n/labels_<lang>.json — the single source of truth shared with the
# Python side, and generic (BirdNET ships 30-odd languages). An English-only station has no
# second name. A species with no localised name falls back to English, which we treat as "no
# second name" so the collage shows English only rather than repeating it.
#
# The struct's `ga` field is the second-language name whatever that language is (named `ga`
# historically, when Irish was the only case); a station's own language decides.
class BirdName
  Name = Data.define(:sci, :en, :ga)

  # The Irish names carry accented characters (á, é, í, ó, ú); read as UTF-8 explicitly so a
  # headless Pi's non-UTF-8 default locale can't mangle them. (LANG/LC_ALL=C.UTF-8 in the units.)
  L18N_DIR = Rails.root.join('../model/l18n')

  class << self
    def lookup(sci)
      en = english.fetch(sci, sci)
      local = secondary[sci]
      ga = local if local && local != en
      Name.new(sci:, en:, ga:)
    end

    # The station's second-language code (the first non-English language it offers), or nil
    # for an English-only station.
    def secondary_language
      Station.languages.map(&:to_s).find { |lang| lang != 'en' }
    end

    # Every scientific name the English label set knows — the universe SpeciesCatalog
    # filters down to whatever a station ships art for.
    def scientific_names
      english.keys
    end

    # Drop the memoized label sets — for specs that swap the active profile mid-run.
    def reset!
      @english = nil
      @secondary = nil
    end

    private

    def english
      @english ||= load('en')
    end

    # Cached per language code, so a station that offers Irish loads labels_ga.json once.
    def secondary
      lang = secondary_language
      return {} unless lang

      (@secondary ||= {})[lang] ||= load(lang)
    end

    def load(lang)
      path = L18N_DIR.join("labels_#{lang}.json")
      path.exist? ? JSON.parse(File.read(path, encoding: 'UTF-8')) : {}
    end
  end
end
