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
      canonical = english.fetch(sci, sci)
      en = overrides[sci] || respell(strip_prefix(canonical))
      local = secondary[sci]
      # A species with no distinct second-language name has the CANONICAL English mirrored into the
      # locale file; compare against that (not the display `en`, which the overlay may have changed)
      # so an overridden/stripped English name doesn't turn that mirror into a bogus "second name".
      # A genuinely missing/wrong Irish name is fixed in the locale file itself, not overridden here.
      ga = local if local && local != canonical
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
      @names_config = nil
      @overrides = nil
      @strip_prefixes = nil
      @replacements = nil
    end

    private

    # The per-station English display overlay (content/bird_names.yml), applied in `lookup` over the
    # canonical ealta label (which stays keyed to BirdNET for detection mapping): an explicit
    # `overrides` map (a spelling — "Greylag" for the label's "Graylag" — or the subspecies we
    # really get — "Pied Wagtail" for "White Wagtail") wins; else a `strip_prefixes` rule drops a
    # leading "Common "/"European "/"Eurasian " so the bare bird stands ("European Robin" → "Robin").
    # A station shipping no bird_names.yml sees the canonical name unchanged.
    def strip_prefix(name)
      prefix = strip_prefixes.find { |p| name.start_with?("#{p} ") && name.length > p.length + 1 }
      prefix ? name.sub("#{prefix} ", '') : name
    end

    # Spelling replacements (British spelling), applied after prefix-stripping: e.g. the American
    # "Gray" → "Grey" so "Gray Heron"/"Graylag" read "Grey Heron"/"Greylag".
    def respell(name)
      replacements.reduce(name) { |acc, (pattern, repl)| acc.gsub(pattern, repl) }
    end

    def overrides
      @overrides ||= names_config['overrides'] || {}
    end

    def strip_prefixes
      @strip_prefixes ||= Array(names_config['strip_prefixes']).map(&:to_s)
    end

    # [Regexp, replacement] pairs from the config's `replace` list — a bad pattern is logged and
    # skipped rather than breaking every name lookup.
    def replacements
      @replacements ||= Array(names_config['replace']).filter_map do |rule|
        pattern, repl = Array(rule)
        next if pattern.blank?

        [Regexp.new(pattern.to_s), repl.to_s]
      rescue RegexpError => e
        Rails.logger.warn("BirdName: skipping bad replace pattern #{pattern.inspect} (#{e.message})")
        nil
      end
    end

    def names_config
      @names_config ||= StationProfile.yaml('content/bird_names.yml').then { |c| c.is_a?(Hash) ? c : {} }
    end

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
