# The station's own curated lore per species (StationProfile → content/bird_lore.yml):
# attributed, public-domain verse and tales. This is a FOLKLORE SOURCE — it stands beside the
# web sources (dúchas and friends), and Enrichment::SeedLore turns each entry into a folklore
# block indistinguishable from a sourced one. This class only reads the content; it's the raw
# reference (same discipline as Feilire), so selection and rotation live downstream where seed
# and web folklore are pooled together.
class BirdLore
  class << self
    # Every curated entry for a species — a species maps to EITHER a single entry or a LIST of
    # them (a bird can hold several poems/tales) — as an array of
    # { 'kind' =>, 'text' =>, 'attribution' => … } hashes; [] when the species has none.
    def entries(sci_name)
      case (raw = StationProfile.yaml('content/bird_lore.yml')[sci_name.to_s])
      when Array then raw
      when Hash  then [raw]
      else []
      end
    end
  end
end
