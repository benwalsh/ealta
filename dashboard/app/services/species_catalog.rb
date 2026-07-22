# The full field-guide library: every species we ship an illustration for — the
# universe the atlas can browse, beyond just what's been heard. Source of truth is
# the illustration manifest (masks.json, one entry per pose), matched back to BirdNET
# scientific names through the shared label file. It reads the manifest rather than
# globbing PNGs so the library is the same everywhere: in the cloud the art bytes live
# on the CDN, not the app's disk, but masks.json ships in the image (see BirdMask).
class SpeciesCatalog
  class << self
    # Every scientific name we have art for, ordered by display (second-language) name.
    def all_sci
      @all_sci ||= BirdName.scientific_names.
                   select { |sci| slugs.include?(sci.downcase.tr(' ', '-')) }.
                   sort_by { |sci| name_key(sci) }
    end

    # Drop the memoized library — for specs that swap the active profile (and thus its art)
    # mid-run; in production the profile is fixed, so this is never called.
    def reset!
      @all_sci = nil
      @slugs = nil
    end

    private

    # Perched illustration slugs (the flight "-2" variants don't count as separate species),
    # from the shared masks.json manifest — NOT a filesystem glob, which finds nothing in the
    # cloud where the PNGs live on the CDN rather than the app's disk (see BirdMask.slugs).
    def slugs
      @slugs ||= BirdMask.slugs.reject { |slug| slug.end_with?('-2') }.to_set
    end

    def name_key(sci)
      name = BirdName.lookup(sci)
      (name.ga || name.en).downcase
    end
  end
end
