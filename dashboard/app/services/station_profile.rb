require 'yaml'

# A station's identity and content live in a PROFILE directory, never hard-coded in the app.
# ealta is the product; a profile is an *instance*. The active
# profile is chosen by the STATION_PROFILE env var (an absolute path); everything falls back —
# per file, not per profile — to the shipped reference profile at stations/example. So an
# overlay ships ONLY the files it overrides and inherits the rest. This is the single seam
# through which a downstream user gives ealta their coordinates, prompts, sources, curated
# lore and language, without touching code.
#
#   StationProfile.read('prompts/day_note.system.md')  # raw string, profile → example → nil
#   StationProfile.yaml('content/bird_lore.yml')        # parsed, {} on absent/bad
#   StationProfile.config                               # station.yml, memoized
class StationProfile
  EXAMPLE = 'example'.freeze

  class << self
    # The active profile directory: STATION_PROFILE if set, else the shipped example.
    def dir
      configured = ENV.fetch('STATION_PROFILE', nil).presence
      @dir ||= configured ? Pathname.new(configured).expand_path : example_dir
    end

    # The reference profile shipped in the repo — the fallback floor, always present.
    def example_dir
      Rails.root.join('..', 'stations', EXAMPLE)
    end

    # Raw UTF-8 file contents from the active profile, else the example, else nil. `relpath`
    # is relative (e.g. 'content/feilire.yml'). Read as UTF-8 explicitly: profiles carry
    # accented text (fadas) and a headless Pi's default locale can be non-UTF-8. Never raises.
    # Cached per path (including a nil miss), so Prompts can read on every request; reset! clears it.
    def read(relpath)
      return raw_cache[relpath] if raw_cache.key?(relpath)

      raw_cache[relpath] = [dir, example_dir].uniq.filter_map do |base|
        path = base.join(relpath)
        path.read(encoding: Encoding::UTF_8) if path.file?
      end.first
    end

    # The resolved filesystem path for relpath (profile → example), or nil when neither
    # has it. For BINARY profile assets — the brand mark, the favicon — which must be
    # served as bytes, not decoded as UTF-8 text the way `read` does.
    def path(relpath)
      [dir, example_dir].uniq.map { |base| base.join(relpath) }.find(&:file?)
    end

    # The resolved directory for relpath (profile → example), or nil when neither has it.
    def dir_path(relpath)
      [dir, example_dir].uniq.map { |base| base.join(relpath) }.find(&:directory?)
    end

    # Where this station's bird illustrations live. The engine ships NONE: art is the
    # output of a station's own style (image/prompt.template.md), so it belongs to the
    # instance, not the product. nil when a station has no art yet — every bird then
    # renders without a picture, which the collage and the species card both handle.
    def illustrations_dir
      dir_path('illustrations')
    end

    # Parsed YAML for relpath (profile → example), or {} when absent or unreadable — the
    # graceful-empty contract BirdLore/Feilire already lean on. Cached per path: in production
    # the profile is fixed, so callers can read on every request without touching disk; a spec
    # that swaps STATION_PROFILE clears the cache via reset!.
    def yaml(relpath)
      cache[relpath] ||= parse_yaml(relpath)
    end

    # The station's own config (station.yml), or {} if none.
    def config
      yaml('station.yml')
    end

    # Forget the active profile and every cached read — for specs that point STATION_PROFILE
    # elsewhere mid-run. In production this is never called.
    def reset!
      @dir = nil
      @cache = nil
      @raw_cache = nil
    end

    private

    def cache
      @cache ||= {}
    end

    def raw_cache
      @raw_cache ||= {}
    end

    def parse_yaml(relpath)
      raw = read(relpath)
      return {} if raw.blank?

      YAML.safe_load(raw) || {}
    rescue Psych::SyntaxError => e
      Rails.logger.warn("StationProfile: bad YAML #{relpath} (#{e.message})")
      {}
    end
  end
end
