# The station's own curated lore per species (StationProfile → content/bird_lore.yml):
# attributed, public-domain verse and tales. This is a FOLKLORE SOURCE — it stands beside the
# web sources (dúchas and friends), and Enrichment::SeedLore turns each entry into a folklore
# block indistinguishable from a sourced one. This class only reads the content; it's the raw
# reference (same discipline as Feilire), so selection and rotation live downstream where seed
# and web folklore are pooled together.
class BirdLore
  # Shared excerpts are keyed "multi:<slug>" instead of a scientific name — a passage where several
  # birds share the scene (a lament for the "corr" that named both crane and heron, an eagle poem
  # true of the sea-eagle and the golden eagle alike). Each entry lists the species it belongs to,
  # so the same verse surfaces under every one of them.
  MULTI_PREFIX = 'multi:'.freeze

  class << self
    # Every curated entry for a species: those keyed directly under its own scientific name (a
    # single entry or a LIST of them — a bird can hold several poems/tales), FOLLOWED by any shared
    # "multi:" excerpts that tag it in their `species` list. [] when the species has none. Entries
    # are { 'kind' =>, 'text'/'quote' =>, 'attribution' => … } hashes.
    def entries(sci_name)
      sci = sci_name.to_s
      data = StationProfile.yaml('content/bird_lore.yml')
      own(data[sci]) + multi(data, sci)
    end

    private

    def own(raw)
      case raw
      when Array then raw
      when Hash  then [raw]
      else []
      end
    end

    # The shared "multi:" excerpts tagged with this species, in a deterministic order (by key),
    # after the bird's own entries. A `species` list is matched exactly against the scientific name.
    def multi(data, sci)
      data.select { |key, _| key.to_s.start_with?(MULTI_PREFIX) }.
        sort_by { |key, _| key.to_s }.
        flat_map { |_key, entries| Array(entries) }.
        select { |entry| Array(entry['species']).map { |s| s.to_s.strip }.include?(sci) }
    end
  end
end
