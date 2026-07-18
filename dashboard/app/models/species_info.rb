require 'net/http'
require 'json'

# Cached species descriptions for the detail panel. When an LLM is configured, the English
# prose is a SMART SUMMARY of the Wikipedia lead section (Bedrock) — the raw first paragraph
# too often opens on naming variants and how-to-tell-it-apart-from-lookalikes trivia (the
# golden plover's "also known as… similar to Pluvialis dominica…"), which is dull and then
# faithfully translated into equally dull Irish. The summary keeps what's characterful about
# the bird and drops the digressions. With no LLM (the offline Pi, a key-less station) it
# falls back to the raw lead paragraph — still real, just less curated.
#
# English is keyed by scientific name (en.wikipedia resolves those). Irish is a faithful
# TRANSLATION of the English (Bedrock), since ga.wikipedia covers only a fraction of species;
# the native ga article is a fallback when the model is unavailable. Fetched once per species
# so the panel doesn't hit the network/model on every open.
class SpeciesInfo < ApplicationRecord
  # Commons licence codes we may reuse in the letter, matched against the machine-readable
  # `License` field: public domain and the attribution CC licences. Deliberately an ALLOWLIST
  # — CC BY-ND/NC variants, fair use and non-free tags all fall through to "no photo", and the
  # letter shows the station's own illustration instead. Refusing when unsure is the only safe
  # default: a misattributed or unlicensed photograph in a mailout is a real liability.
  FREE_LICENCE = /\A(cc0|cc-by(-sa)?(-\d|\z)|pd|public.?domain)/
  # Distil the Wikipedia lead into a warm, readable description of the BIRD — not its
  # nomenclature. Summarise only from the supplied text; add no outside knowledge.
  SUMMARISE_DESC = <<~PROMPT.freeze
    You are writing the short description shown when someone taps a bird in a birdsong app.
    From the Wikipedia text below, write 2–3 sentences on what makes THIS bird itself: how it
    looks, how it behaves, its voice, where and how it lives. Draw ONLY from the text given —
    add nothing from your own knowledge, and if the text is thin, keep it short rather than
    invent. Skip the encyclopedic throat-clearing: alternative common names, who named it,
    and how it differs from similar species are NOT interesting here — leave them out. Plain,
    warm, present tense. No preamble, no headings — return only the description prose.
  PROMPT

  # A faithful Irish rendering of the English summary, using the established Irish bird name.
  TRANSLATE_DESC = <<~PROMPT.freeze
    Translate this bird's species description into natural, idiomatic Irish (Gaeilge), with
    correct spelling and síntí fada. Where the text names the bird, use its established Irish
    name%<name>s. A faithful translation — add nothing, drop nothing, no preamble or notes.
    Return only the Irish prose.
  PROMPT

  # How much of the English article to hand the summariser: the opening ~4000 characters,
  # NOT just the lead. Many bird articles open on a short nomenclature paragraph and keep
  # the behaviour/voice/habitat down in Description and Distribution — exactly the
  # interesting part a lead-only fetch misses (see fetch_lead).
  LEAD_CHARS = 4000

  validates :sci_name, presence: true, uniqueness: true

  class << self
    def english_for(sci, common = nil)
      info = find_or_initialize_by(sci_name: sci)
      return info.description if info.description.present?

      text, from_model = describe(sci, common)
      # Only keep what we meant to produce. With a model configured, a failed summary means
      # try again on the next detection — NOT "this bird's description is the raw Wikipedia
      # lead forever". Freezing the fallback is how a transient Bedrock blip used to leave a
      # species permanently showing nomenclature trivia, and preparing content automatically
      # (PrepareSpeciesContentJob) would otherwise make that far easier to hit. With no model
      # configured at all, the lead IS the intended answer, so it caches normally.
      info.update(description: text, fetched_at: Time.current) if text && (from_model || !Bedrock.available?)
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

    # The hero photograph for a species — { url:, credit: } — or nil when there is none.
    #
    # FOR THE NEWSLETTER ONLY. The website never shows a photograph: it is the e-ink panel's
    # voice, and dithered illustrations on paper are the whole aesthetic. A letter arriving in
    # a mail client is a different surface, and one real photograph of the day's bird earns
    # its place there. Nothing in the web app calls this, and nothing should — the species
    # card, the API and the panel all stay on the station's own art.
    #
    # fetched_photo_at records the attempt — including a miss — so a species is looked up once
    # rather than on every send. nil means no usable photo, and the letter's hero_banner falls
    # back to the illustration, which is a perfectly good outcome rather than a failure.
    def photo_for(sci)
      info = find_or_initialize_by(sci_name: sci)
      return stored_photo(info) if info.fetched_photo_at.present?

      photo = fetch_photo(sci)
      info.update(photo_url: photo&.fetch(:url), photo_credit: photo&.fetch(:credit),
                  fetched_photo_at: Time.current)
      photo
    end

    # Is everything the species modal needs already stored, so opening it is a pure DB read?
    # Both descriptions and the song. The song counts as ready when the curated manifest covers
    # it, because url_for then resolves without ever touching SpeciesInfo (so fetched_song_at
    # stays nil forever and would otherwise read as permanently cold).
    #
    # One definition, used by all three callers — the ingest hook deciding what to enqueue, the
    # job re-checking before it spends on a model, and the warm rake task — so they cannot drift.
    def content_ready?(sci, info = find_by(sci_name: sci))
      return false if info.nil?

      info.description.present? && info.fetched_ga_at.present? &&
        (SongSample.bundled?(sci) || info.fetched_song_at.present?)
    end

    # Which of these species still need preparing. One query rather than one per species: an
    # ingest batch can carry a good few, and this runs on the Pi's push path.
    def missing_content(sci_names)
      names = Array(sci_names).compact.uniq
      return [] if names.empty?

      by_name = where(sci_name: names).index_by(&:sci_name)
      names.reject { |sci| content_ready?(sci, by_name[sci]) }
    end

    private

    # The English description: an LLM summary of the Wikipedia lead when a model is
    # configured, else the raw lead paragraph. Both draw on Wikipedia by scientific name,
    # falling back to the common name (some articles resolve only under the vernacular).
    # Returns [text, from_model] — the caller needs the provenance to decide whether the
    # result is worth freezing (see english_for), since the fallback is a stand-in rather
    # than the answer we wanted.
    def describe(sci, common)
      if Bedrock.available?
        lead = fetch_lead(sci) || (common && fetch_lead(common))
        summary = lead && summarise(lead)
        return [summary, true] if summary.present?
      end
      # No model, or the summary failed: the plain first-paragraph extract.
      [fetch(sci, 'en') || (common && fetch(common, 'en')), false]
    end

    # Wikipedia lead → a warm 2–3 sentence description of the bird via Bedrock. Uses the
    # stronger enrich model (the panel text is read closely; Nova Lite is terser and blander)
    # and is cached per species. nil on a disabled/failed model so describe() falls back.
    def summarise(lead)
      return nil if lead.blank? || !Bedrock.available?

      Bedrock.converse(system: SUMMARISE_DESC, user: lead,
                       model_id: Bedrock.enrich_model_id, max_tokens: 400).presence
    rescue StandardError => e
      Rails.logger.warn("SpeciesInfo: description summary failed (#{e.class}: #{e.message})")
      nil
    end

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

    # A stored photo as the letter's pair, or nil. A photo we cannot credit is treated as no
    # photo: we only ever stored one whose licence and attribution we resolved, so a blank
    # credit means something went wrong and the illustration is the safer answer.
    def stored_photo(info)
      return nil if info.photo_url.blank? || info.photo_credit.blank?

      { url: info.photo_url, credit: info.photo_credit }
    end

    # The species' LEAD image from its Wikipedia article — curated onto that exact article, so
    # it is the bird rather than whatever a bare image search dredges up (the same reasoning
    # as article_song). Returns { url:, credit: } only when the licence permits reuse AND the
    # credit can be built; otherwise nil.
    def fetch_photo(sci)
      title = get_json('https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1' \
                       '&prop=pageimages&piprop=name&titles=' \
                       "#{ERB::Util.url_encode(sci.tr(' ', '_'))}")&.
              dig('query', 'pages')&.values&.first&.dig('pageimage')
      return nil if title.blank?

      photo_from_commons("File:#{title}")
    rescue StandardError
      nil
    end

    # A Commons File: title → { url:, credit: }, gated on its licence metadata.
    def photo_from_commons(title)
      meta = get_json('https://commons.wikimedia.org/w/api.php?action=query&format=json' \
                      '&prop=imageinfo&iiprop=url%7Cextmetadata&titles=' \
                      "#{ERB::Util.url_encode(title)}")&.
             dig('query', 'pages')&.values&.first&.dig('imageinfo', 0)
      return nil if meta.blank?

      extra = meta['extmetadata'] || {}
      licence = licence_label(extra)
      url = meta['url']
      return nil if url.blank? || licence.blank?

      credit = [attribution(extra), licence].compact_blank.join(' · ')
      credit.present? ? { url: url, credit: credit } : nil
    end

    # The licence, but ONLY when it is one that permits reuse. Commons' machine-readable
    # `License` code is the thing to test — the human LicenseShortName is free text. Anything
    # unrecognised (fair use, non-free promotional, a bare "used with permission") returns nil
    # and the photo is dropped: showing an image we cannot license is a legal fault, not a
    # cosmetic one, so the rule is allowlist and refuse when unsure. Restrictions (trademark,
    # personality rights) also disqualify — those need a judgement no automated send can make.
    def licence_label(extra)
      code = extra.dig('License', 'value').to_s.downcase
      return nil unless code.match?(FREE_LICENCE)
      return nil if extra.dig('Restrictions', 'value').to_s.strip.present?

      strip_markup(extra.dig('LicenseShortName', 'value')).presence || code.upcase
    end

    # The photographer. Commons returns this as an HTML fragment (usually a link to a user
    # page), so it is stripped to text. Blank for public-domain works, which is legitimate —
    # PD/CC0 carry no attribution requirement, so the licence alone is a complete credit.
    def attribution(extra)
      strip_markup(extra.dig('Artist', 'value')).presence ||
        strip_markup(extra.dig('Credit', 'value')).presence
    end

    def strip_markup(html)
      return nil if html.blank?

      ActionView::Base.full_sanitizer.sanitize(html.to_s).to_s.squish
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

    # The opening LEAD_CHARS of the English article as raw material for the summary.
    # exchars truncates server-side at a word boundary; the summary prompt ignores the
    # naming throat-clearing at the top.
    def fetch_lead(title)
      json = get_json('https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1' \
                      "&prop=extracts&explaintext=1&exchars=#{LEAD_CHARS}&titles=" \
                      "#{ERB::Util.url_encode(title.tr(' ', '_'))}")
      page = json&.dig('query', 'pages')&.values&.first
      page && page['missing'].nil? ? page['extract'].presence : nil
    rescue StandardError
      nil
    end
  end
end
