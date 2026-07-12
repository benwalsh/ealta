# The listening station's own identity — its place — resolved from config or an API
# lookup, NEVER hard-coded. ealta is the product; a station is an *instance* defined
# entirely by configuration. So no view, prompt or
# component names a location literally: they all ask here, and get whatever this
# instance is configured/resolved to be (or nothing, gracefully).
class Station
  # The panel speaks ONE language, consistently — an admin picks which at /admin (stored
  # in Setting, so no redeploy). WHICH languages a station offers, and its default, are
  # config (station.yml: languages, default_language); the code names no language. A
  # single-language station simply never translates. a station may be Irish-first ([ga, en]);
  # the shipped example is English-only.
  LANGUAGE_SETTING = 'station_language'.freeze
  # Display names for a language code; falls back to the code itself for anything unlisted.
  LANGUAGE_NAMES = { ga: 'Gaeilge', en: 'English', fr: 'Français', de: 'Deutsch',
                     es: 'Español', cy: 'Cymraeg', nl: 'Nederlands' }.freeze

  class << self
    # One dotted lookup for station.yml's service settings — the Devise-initializer pattern:
    # every option ships commented-out in stations/example/station.yml with its default; a
    # station uncomments what it opts into. Precedence: ENV (deploy/secret override) → the
    # profile's station.yml → the built-in default. Secrets never live in the YAML — an env
    # name is passed by the caller precisely so keys/passwords stay in .env.
    #
    #   Station.setting('llm.region', env: 'BEDROCK_REGION', default: nil)
    def setting(path, env: nil, default: nil)
      override = env && ENV[env].presence
      return override if override

      value = path.to_s.split('.').reduce(StationProfile.config) do |node, key|
        node.is_a?(Hash) ? node[key] : nil
      end
      value.nil? || (value.respond_to?(:empty?) && value.empty?) ? default : value
    end

    # The languages this station offers, most-preferred first (from station.yml), or [:en].
    def languages
      Array(StationProfile.config['languages']).map { |l| l.to_s.to_sym }.presence || %i[en]
    end

    # The station's default/first-choice language — config, then the STATION_LANG env
    # override (legacy), then the first offered language.
    def default_language
      value = (StationProfile.config['default_language'].presence || ENV['STATION_LANG'].presence)&.to_sym
      value && languages.include?(value) ? value : languages.first
    end

    # True when the station shows more than one language — the only case the translation
    # pass and the second-language name are engaged at all.
    def multilingual?
      languages.size > 1
    end

    # The display name of a language code, for the admin picker.
    def language_name(code)
      LANGUAGE_NAMES.fetch(code.to_sym, code.to_s)
    end

    # What this station calls itself — in the masthead, page titles and emails. The
    # engine names itself nowhere; a station says what it is called (station.yml:
    # site_name). Falls back to the product name so an unnamed station still renders.
    def site_name
      StationProfile.config['site_name'].presence || 'Ealta'
    end

    # station.yml's `brand` block: the mark, its bilingual alt text, the favicon.
    def brand
      StationProfile.config['brand'] || {}
    end

    # Bilingual alt text for the masthead mark, falling back to the station's name.
    def mark_alt
      alt = brand['mark_alt'] || {}
      en = alt['en'].presence || site_name
      { en: en, ga: alt['ga'].presence || en }
    end

    # The resolved path to a brand asset (:mark or :favicon), or nil when the profile
    # (and the example floor) ship neither. Callers must handle nil — a station is
    # entitled to have no mark.
    def brand_asset(kind)
      rel = brand[kind.to_s].presence
      rel && StationProfile.path(rel)
    end

    # The panel's current display language. Setting wins, then the config default; an
    # unknown stored value falls back safely to the default.
    def language
      value = Setting.get(LANGUAGE_SETTING, default_language).to_s.to_sym
      languages.include?(value) ? value : default_language
    end

    # Set by the admin surface. Rejects anything the station doesn't offer, so a bad post
    # can't wedge the wall into a language it can't render.
    def language=(value)
      value = value.to_s.to_sym
      raise ArgumentError, "unknown station language #{value.inspect}" unless languages.include?(value)

      Setting.set(LANGUAGE_SETTING, value)
    end

    # A polite User-Agent for the station's own outbound fetches (weather, tide) — identifies
    # the app and, when a site is configured, this instance's URL as a contact. Never hard-coded.
    def user_agent
      host = url.to_s.sub(%r{\Ahttps?://}, '').presence
      host ? "ealta/1.0 (+https://#{host})" : 'ealta/1.0'
    end

    # Where a guest goes to see more — this instance's public site, shown as calm
    # wayfinding on the panel. Config (station.yml url), then the STATION_URL env, else nil.
    # Never hard-coded to a particular site.
    def url
      StationProfile.config['url'].presence || ENV['STATION_URL'].presence
    end

    # A bilingual place label, or nil if nothing is configured or resolved. station.yml
    # place wins (a fixed station), then the BIRD_PLACE env, then the almanac's
    # reverse-geocode; the word is never in our code. The `:ga` key is the second-language
    # name (whatever the station's local language is), falling back to the English label.
    def place
      cfg = StationProfile.config['place'] || {}
      en = cfg['en'].presence || ENV['BIRD_PLACE'].presence || almanac_place[:en].presence
      return nil if en.blank?

      { en: en, ga: cfg['ga'].presence || ENV['BIRD_PLACE_GA'].presence || almanac_place[:ga].presence || en }
    end

    # A single-language place string for prose contexts (the LLM prompt), or nil.
    def region
      place&.fetch(:en, nil)
    end

    private

    def almanac_place
      value = (Almanac.current[:coords] || {})[:place]
      value.is_a?(Hash) ? value : { en: value, ga: value }
    end
  end
end
