# Curated literary/folkloric lore per species — attributed, public-domain verse and tales
# quoted verbatim to round off a Journal entry. The model never writes these; the reference
# supplies the exact, credited text (same discipline as Feilire). The content is a station's
# own (StationProfile → content/bird_lore.yml), so each place brings its own tradition.
# Returns a string-keyed { 'kind' =>, 'text' =>, 'attribution' => } hash, or nil.
class BirdLore
  class << self
    def for(sci_name)
      StationProfile.yaml('content/bird_lore.yml')[sci_name.to_s]
    end
  end
end
