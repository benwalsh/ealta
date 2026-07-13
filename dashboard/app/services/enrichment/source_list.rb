module Enrichment
  # The station's source allowlist and folklore/regional preferences, read from the profile's
  # sources.yml (profile → example). This is the ONE place a station declares which hosts its
  # enrichment researcher may fetch and which bespoke adapters to enable — a downstream station
  # adds a source by editing this file, not the fetcher and a prompt. `prefer_note` is the
  # prose the enrichment prompt injects to tell the model which sources to favour.
  class SourceList
    attr_reader :adapters, :prefer_note

    class << self
      def current
        config = StationProfile.yaml('sources.yml')
        # Legacy location (pre-rationalisation profiles) — remove once every station has moved.
        config = StationProfile.yaml('sources/allowlist.yml') unless config.is_a?(Hash) && config.any?
        new(config)
      end
    end

    def initialize(config)
      config = {} unless config.is_a?(Hash)
      @hosts = Array(config['trusted_hosts']).to_set { |h| h.to_s.downcase }
      pattern = config['affiliate_pattern'].to_s.strip
      @affiliate = pattern.empty? ? nil : Regexp.new(pattern)
      @adapters = Array(config['adapters']).map(&:to_s)
      @prefer_note = config['prefer_note'].to_s.strip
    end

    # Trusted if the host is on the exact list or matches the affiliate pattern (e.g. BirdWatch
    # county branches). Never trusts a blank host. Case-insensitive.
    def trusted?(host)
      return false if host.blank?

      h = host.to_s.downcase
      @hosts.include?(h) || @affiliate&.match?(h) || false
    end
  end
end
