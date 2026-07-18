module Enrichment
  # The attribution dúchas.ie REQUIRES for reuse of Schools'-Collection material under its
  # CC BY-NC 4.0 licence (https://www.duchas.ie/en/info/contact):
  #
  #   "The Schools' Collection, Volume 0199, Page 012" by Dúchas
  #   © National Folklore Collection, UCD is licensed under CC BY-NC 4.0
  #
  # rendered with the collection reference linking the human /en/cbes/ page and the licence
  # linking its deed. This module is the SINGLE place that shape is built, so the two folklore
  # springs — curated bird_lore.yml entries (SeedLore) and the live fallback (Adapters::Duchas)
  # — credit dúchas identically and to their stated terms. It returns the source hash the display
  # layer already threads to the card ({ host:, url:, holder:, licence:, licence_url:, … }); the
  # reference goes in `host` (linked by `url`), so nothing downstream needs to know it is dúchas.
  #
  # Beyond the licence, we also surface the COLLECTOR/informant/school when known — the 1930s
  # schoolchildren and their teachers who recorded the lore — as a quiet provenance line. That is
  # folklore ethics, not a licence requirement: credit the people the material came from.
  module DuchasCitation
    COLLECTION = "The Schools' Collection".freeze
    HOLDER = '© National Folklore Collection, UCD'.freeze
    LICENCE = 'CC BY-NC 4.0'.freeze
    LICENCE_URL = 'https://creativecommons.org/licenses/by-nc/4.0/'.freeze

    module_function

    # A dúchas citation → the source hash. `volume`/`page` build the required reference; `url` is
    # the human /en/cbes/ page (never the /xml/ or beta endpoint); `collector`/`informant`/`school`
    # are the optional provenance credit. Blank fields drop out, so a citation missing (say) a page
    # still yields a correct, if shorter, reference.
    def source(url:, volume: nil, page: nil, collector: nil, informant: nil, school: nil,
               collection: COLLECTION)
      { host: reference(collection, volume, page), url: url.to_s.strip.presence,
        holder: HOLDER, licence: LICENCE, licence_url: LICENCE_URL,
        collector: collector.to_s.strip.presence, informant: informant.to_s.strip.presence,
        school: school.to_s.strip.presence }.compact
    end

    # "The Schools' Collection, Volume 0199, Page 012" — the linked reference dúchas asks for,
    # gracefully dropping a missing volume or page.
    def reference(collection, volume, page)
      [collection.to_s.strip.presence || COLLECTION,
       ("Volume #{volume}" if volume.to_s.strip.present?),
       ("Page #{page}" if page.to_s.strip.present?)].compact.join(', ')
    end
  end
end
