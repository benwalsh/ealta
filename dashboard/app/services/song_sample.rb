require 'json'

# Resolves the playable call/song sample for a species. A curated manifest
# (model/songs.json: scientific name → audio URL) takes priority — that's where
# self-hosted clips (e.g. an S3 bucket) go, to fill gaps where Wikipedia has no
# recording or to override a poor one. Anything not in the manifest falls back
# to the Wikimedia Commons audio on the species' Wikipedia article.
class SongSample
  MANIFEST_PATH = Rails.root.join('../model/songs.json')

  class << self
    # A playable audio URL, or nil if neither a curated clip nor a Wikipedia
    # recording exists (the player is hidden in that case).
    def url_for(sci)
      manifest[sci].presence || SpeciesInfo.song_for(sci)
    end

    # Is this species covered by the curated manifest? Then url_for resolves without touching
    # the network or SpeciesInfo at all — so the cache-warmer must not read a blank
    # fetched_song_at as "still cold" and re-warm it on every run.
    def bundled?(sci)
      manifest[sci].present?
    end

    private

    def manifest
      @manifest ||= MANIFEST_PATH.exist? ? JSON.parse(MANIFEST_PATH.read) : {}
    end
  end
end
