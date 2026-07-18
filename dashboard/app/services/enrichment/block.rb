module Enrichment
  # A typed, self-contained, pre-cited block — the Stage-1 → Stage-2 contract between
  # Claude (which sources and writes them) and Nova (which selects, orders and frames
  # them). Nova may drop, reorder and introduce blocks with glue prose; it may never
  # edit the inside of one or synthesise a new one. Every block is validated on the way
  # in (Builder) and on the way out (bundle, assembly validator), so a malformed or
  # unsourced block never reaches a subscriber.
  class Block
    TYPES = %w[fact regional_note folklore station_reading].freeze
    # station_reading is the station's OWN data — the only type allowed zero sources.
    SOURCELESS_TYPES = %w[station_reading].freeze
    # Every field a source may carry, in display order — the citation contract, named ONCE.
    # The display layer used to hand-list these and had already drifted from the producers:
    # DuchasCitation emits `informant` and `school` (the 1930s schoolchildren and teachers the
    # lore came from — folklore ethics, not a licence term) and both were being dropped on the
    # floor before the card ever saw them. Add a field here and it threads through by itself.
    SOURCE_FIELDS = %i[host url holder licence licence_url collector informant school].freeze

    attr_reader :attrs

    class << self
      # Build from a stored/produced hash (string- or symbol-keyed); nil for non-hashes.
      def from(raw)
        return nil unless raw.respond_to?(:to_h)

        new(raw.to_h.deep_symbolize_keys)
      end
    end

    def initialize(attrs)
      @attrs = attrs
    end

    def type = attrs[:type]
    def id = attrs[:id]
    def text = attrs[:text]
    # the Irish rendering, produced alongside `text`; may be nil
    def text_ga = attrs[:text_ga]
    def sources = Array(attrs[:sources])
    def gated? = attrs[:gated] == true
    def to_h = attrs

    def valid?
      errors.empty?
    end

    # Every way this block breaks the contract (empty array = valid).
    def errors
      e = []
      e << "unknown type #{type.inspect}" unless TYPES.include?(type)
      e << 'blank id' if id.to_s.strip.empty?
      e << 'missing source' if sources.empty? && SOURCELESS_TYPES.exclude?(type)
      e << 'folklore must be gated' if type == 'folklore' && !gated?
      e
    end
  end
end
