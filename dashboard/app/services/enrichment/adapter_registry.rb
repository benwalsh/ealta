module Enrichment
  # Builds the enabled source adapters for a fetcher from the profile's `adapters:` list. An
  # adapter named in config but unknown here is ignored (a typo must not crash enrichment); the
  # fetcher's generic HTML path always remains as the floor.
  module AdapterRegistry
    AVAILABLE = { 'duchas' => Adapters::Duchas }.freeze

    class << self
      def enabled(names, fetcher)
        Array(names).filter_map { |name| AVAILABLE[name.to_s]&.new(fetcher) }
      end
    end
  end
end
