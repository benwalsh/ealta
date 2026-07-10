require 'net/http'
require 'json'

# Cached Wikipedia species descriptions for the detail panel. English prose is keyed by
# scientific name (en.wikipedia resolves those). Irish prose is a faithful TRANSLATION of
# that English summary (Bedrock) — Irish Wikipedia covers only a fraction of species and is
# usually sparse, so translating the richer English reads far better; the native ga.wikipedia
# article is only a fallback when the model is unavailable (e.g. the offline Pi). Fetched
# once per species so the panel doesn't hit the network/model on every open.
class SpeciesInfo < ApplicationRecord
  # A faithful Irish rendering of the English summary, using the established Irish bird name.
  TRANSLATE_DESC = <<~PROMPT.freeze
    Translate this bird's species description into natural, idiomatic Irish (Gaeilge), with
    correct spelling and síntí fada. Where the text names the bird, use its established Irish
    name%<name>s. A faithful translation — add nothing, drop nothing, no preamble or notes.
    Return only the Irish prose.
  PROMPT

  validates :sci_name, presence: true, uniqueness: true

  class << self
    def english_for(sci, common = nil)
      info = find_or_initialize_by(sci_name: sci)
      return info.description if info.description.present?

      text = fetch(sci, 'en') || (common && fetch(common, 'en'))
      info.update(description: text, fetched_at: Time.current) if text
      text
    end

    # The bird's Irish description: a translation of the (richer) English summary, or the
    # native Irish Wikipedia article when the model is unavailable. fetched_ga_at records the
    # attempt — including a miss — so a species is only translated/fetched once.
    def irish_for(sci, ga_name)
      info = find_or_initialize_by(sci_name: sci)
      return info.description_ga if info.fetched_ga_at.present?

      text = translate_to_irish(english_for(sci), ga_name)
      text ||= fetch(ga_name, 'ga') if ga_name.present?
      info.update(description_ga: text, fetched_ga_at: Time.current)
      text
    end

    # A playable call/song sample (a Wikimedia Commons audio URL) for the inline
    # player. fetched_song_at records the attempt — including a miss (some species
    # have no recording) — so we don't re-hit Wikipedia on every modal open.
    def song_for(sci)
      info = find_or_initialize_by(sci_name: sci)
      return info.song_url if info.fetched_song_at.present?

      url = fetch_song(sci)
      info.update(song_url: url, fetched_song_at: Time.current)
      url
    end

    private

    # English summary → a faithful Irish rendering via Bedrock (max_tokens raised for a
    # multi-sentence description). nil when there's nothing to translate, the model is
    # disabled (offline Pi), or the call fails — the caller then falls back to ga.wikipedia.
    def translate_to_irish(english, ga_name)
      return nil if english.blank? || Bedrock.disabled?

      name = ga_name.present? ? " (#{ga_name})" : ''
      # Translate with the stronger enrich model (Claude), not Nova Lite — idiomatic Irish
      # with correct fadas is the centrepiece; the weaker model mangles it. Cached per species.
      Bedrock.converse(system: format(TRANSLATE_DESC, name: name), user: english,
                       model_id: Bedrock.enrich_model_id, max_tokens: 900).presence
    rescue StandardError => e
      Rails.logger.warn("SpeciesInfo: Irish translation failed (#{e.class}: #{e.message})")
      nil
    end

    # Two sources, most-trustworthy first: audio embedded in the species'
    # Wikipedia article, else a Commons search. nil if neither has a recording.
    def fetch_song(sci)
      article_song(sci) || commons_song(sci)
    rescue StandardError
      nil
    end

    # Audio embedded in the species' English Wikipedia article (by scientific
    # name — it redirects to the common-name page). Reliable: it's curated onto
    # that exact article.
    def article_song(sci)
      media = get_json("https://en.wikipedia.org/api/rest_v1/page/media-list/#{ERB::Util.url_encode(sci.tr(' ', '_'))}")
      audio = media && Array(media['items']).find { |item| item['type'] == 'audio' }
      audio && audio['title'].present? ? file_url(audio['title']) : nil
    end

    # Fallback: search Wikimedia Commons for an audio file — but accept only one
    # whose filename contains the scientific name. That filter is essential: a
    # bare search for a species Commons has no recording of returns junk (a
    # same-named food dish, an unrelated speech); requiring the binomial in the
    # title rejects those while keeping genuine "Genus_species_...XC12345" clips.
    def commons_song(sci)
      query = ERB::Util.url_encode("#{sci} filetype:audio")
      res = get_json('https://commons.wikimedia.org/w/api.php?action=query&format=json' \
                     "&generator=search&gsrsearch=#{query}&gsrnamespace=6&gsrlimit=8" \
                     '&prop=imageinfo&iiprop=url%7Cmediatype')
      needle = sci.downcase.tr(' ', '_')
      match = Array(res&.dig('query', 'pages')&.values).find do |page|
        info = page.dig('imageinfo', 0)
        info && info['mediatype'] == 'AUDIO' &&
          page['title'].to_s.downcase.tr(' ', '_').include?(needle)
      end
      match&.dig('imageinfo', 0, 'url')
    end

    # A File: page title → its playable media URL.
    def file_url(title)
      info = get_json('https://en.wikipedia.org/w/api.php?action=query&format=json' \
                      "&prop=imageinfo&iiprop=url&titles=#{ERB::Util.url_encode(title)}")
      info&.dig('query', 'pages')&.values&.first&.dig('imageinfo', 0, 'url')
    end

    def get_json(url)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 8) do |http|
        http.get(uri.request_uri, 'User-Agent' => 'ealta/1.0 (bird detector)')
      end
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    end

    def fetch(title, lang)
      uri = URI("https://#{lang}.wikipedia.org/api/rest_v1/page/summary/#{ERB::Util.url_encode(title.tr(' ', '_'))}")
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 8) do |http|
        http.get(uri.request_uri, 'User-Agent' => 'ealta/1.0 (bird detector)')
      end
      return nil unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body)
      return nil if data['type'] == 'disambiguation'

      data['extract'].presence
    rescue StandardError
      nil
    end
  end
end
