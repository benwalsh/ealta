require 'net/http'
require 'json'

module Enrichment
  # The no-LLM enrichment default. A station that hasn't configured an LLM (see
  # Bedrock.available?) still needs facts to show, so we take a bird's blurb verbatim from
  # Wikipedia: the English summary as `text`, the Irish (ga.wikipedia.org) summary as `text_ga`
  # when the article exists. One cited `fact` block per species, no model call — honest and
  # sourced ("Ruby computes, the source states") rather than silent or invented. A station that
  # later sets BEDROCK_* graduates to the richer Builder (Claude sourcing + typed blocks).
  class Wikipedia
    SUMMARY = 'https://%<lang>s.wikipedia.org/api/rest_v1/page/summary/%<title>s'.freeze
    TIMEOUT = 6

    class << self
      # A one-element array with the species' fact block, or [] when Wikipedia has no article.
      # Shaped exactly like a Builder block so build_one stores and to_display renders it the
      # same way.
      def blocks_for(sci_name:, common_name:)
        en = summary('en', [sci_name, common_name])
        return [] unless en

        # ga.wikipedia.org files birds under their Irish name (Lon dubh, not Turdus merula), so
        # try that first; the scientific name is a fair fallback.
        irish = BirdName.lookup(sci_name).ga
        ga = summary('ga', [irish, sci_name, common_name])
        sources = [{ host: 'en.wikipedia.org', url: en[:url] }]
        sources << { host: 'ga.wikipedia.org', url: ga[:url] } if ga

        block = Block.from(
          type:    'fact',
          id:      "wikipedia-#{sci_name.parameterize}",
          text:    en[:extract],
          text_ga: ga && ga[:extract],
          sources: sources
        )
        block&.valid? ? [block] : []
      end

      private

      # The first title (scientific, then common) that resolves to a real article summary in
      # `lang`. Skips disambiguation pages. Returns { extract:, url: } or nil.
      def summary(lang, titles)
        titles.compact.uniq.each do |title|
          data = fetch(lang, title)
          next unless data && data['type'] != 'disambiguation' && data['extract'].to_s.strip.present?

          return { extract: data['extract'].strip, url: data.dig('content_urls', 'desktop', 'page') }
        end
        nil
      end

      def fetch(lang, title)
        slug = URI.encode_www_form_component(title.tr(' ', '_'))
        uri = URI(format(SUMMARY, lang: lang, title: slug))
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
          http.get(uri.request_uri, 'User-Agent' => Station.user_agent)
        end
        res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
      rescue StandardError
        nil
      end
    end
  end
end
