# Curated literary/folkloric lore per species — attributed, public-domain verse and tales
# quoted verbatim to round off a Journal entry. The model never writes these; the reference
# supplies the exact, credited text (same discipline as Feilire). The content is a station's
# own (StationProfile → content/bird_lore.yml), so each place brings its own tradition.
#
# A species maps to EITHER a single entry or a LIST of them — a bird can hold several poems or
# tales. `for` returns one { 'kind' =>, 'text' =>, 'attribution' => … } hash, chosen by day so
# the pick is stable within a day and rotates across days; nil when the species has none.
class BirdLore
  class << self
    def for(sci_name, date: nil)
      raw = StationProfile.yaml('content/bird_lore.yml')[sci_name.to_s]
      entries = case raw
                when Array then raw
                when Hash  then [raw]
                else return nil
                end
      return nil if entries.empty?

      # Rotate across days rather than always showing the first, but stay fixed within a day
      # (and for any given past day) so a Journal entry reads the same each time it's opened.
      entries[(date ? date.to_date : Date.current).jd % entries.size]
    end
  end
end
