# Relabel a mis-identified detection to the correct species — an admin fixing an obvious
# BirdNET error from the panel. The scientific name is validated against the known BirdNET
# labels before anything is written; the row's Sci_Name and Com_Name are updated together so
# the two never disagree. Replaces scripts/birdnet_changeidentification.sh (which also renamed
# per-detection audio files — this stack keeps none).
class DetectionCorrection
  class << self
    def apply(id, sci_name:)
      sci_name = sci_name.to_s.strip
      detection = Detection.find_by(id: id)
      return { ok: false, message: "detection ##{id} not found" } unless detection
      return { ok: false, message: "unknown species #{sci_name.inspect}" } unless known?(sci_name)

      name = BirdName.lookup(sci_name)
      detection.update!(Sci_Name: sci_name, Com_Name: name.en)
      { ok: true, message: "relabelled ##{id} → #{name.en} (#{sci_name})" }
    end

    private

    # BirdName.lookup falls back to the scientific name as the English name when it's unknown,
    # so a real label is one whose English name differs from the sci-name we looked up.
    def known?(sci_name)
      return false if sci_name.blank?

      BirdName.lookup(sci_name).en != sci_name
    end
  end
end
