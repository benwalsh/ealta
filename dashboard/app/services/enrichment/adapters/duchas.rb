require 'cgi'
require 'erb'
require 'json'

module Enrichment
  module Adapters
    # dúchas.ie (the Schools' Collection) needs bespoke handling: its on-site search is a
    # client-side JS app that returns nothing to a server fetch, so a SEARCH goes through the
    # open JSON API instead; and a STORY page is read from its clean open-data XML transcript
    # while still cited by the human /en/ URL. Browse/index pages are left to the fetcher's
    # generic HTML path. Enabled per station via sources.yml (adapters: [duchas]); it
    # only ever fetches through the fetcher's own allowlist-checked http_get, never its own
    # connection — so the security boundary stays in SourceFetcher.
    class Duchas
      # dúchas's real full-text search — called from this hardcoded constant, never a
      # model-supplied URL, so beta.duchas.ie stays OFF the trusted allowlist.
      SEARCH_API = 'https://beta.duchas.ie/api/en/cbes/transcripts'.freeze
      RESULTS = 10 # transcripts per search (the model picks the on-topic ones)
      SNIPPET = 700
      STORY = %r{\Ahttps?://(?:www\.)?duchas\.ie/en/cbes/\d}

      def initialize(fetcher)
        @fetcher = fetcher
      end

      # Claim a dúchas SEARCH or STORY url; leave anything else on dúchas to the generic path.
      def matches?(url)
        host = SourceFetcher.host_of(url)
        return false unless host&.include?('duchas.ie')

        search_term(url).present? || url.to_s.match?(STORY)
      end

      # { host:, url:, text: } or { error: } — mirrors SourceFetcher#fetch's contract. A story
      # page is fetched via its clean XML transcript but cited by the /en/ URL the model
      # followed (so the block's source matches the fetch log); if that body isn't a transcript
      # after all, fall back to the fetcher's generic HTML extraction.
      def fetch(url, host)
        term = search_term(url)
        return search(url, host, term) if term.present?

        body = @fetcher.http_get(xml_url(url))
        return { error: "fetch failed: #{url}" } unless body

        @fetcher.log!(host, url)
        text = body.include?('<transcript') ? extract_xml(body) : @fetcher.extract_text(body, url)
        { host: host, url: @fetcher.utf8(url), text: text }
      end

      private

      # The search term if this is a Schools'-Collection search (…?Search=… / ?SearchText=…).
      def search_term(url)
        return nil unless url.to_s.match?(/[?&]search(?:text)?=/i)

        CGI.unescape(url[/[?&]search(?:text)?=([^&]+)/i, 1].to_s).strip.presence
      end

      # Run the full-text search through the JSON API and return each matching story's text with
      # a citable /en/ URL. Every story URL is logged so the model may cite the one it retells
      # (many matches are false — "chough" also hits "whooping cough" — so the model must pick
      # the story genuinely about the bird).
      def search(search_url, host, term)
        body = @fetcher.http_get("#{SEARCH_API}?SearchText=#{ERB::Util.url_encode(term)}&Page=1&PerPage=#{RESULTS}")
        entries = body ? Array(JSON.parse(body)['entries']) : []
        @fetcher.log!(host, search_url)
        return { error: "no dúchas stories for '#{term}'" } if entries.empty?

        text = entries.map { |hit| entry(hit) }.join("\n\n").first(SourceFetcher::MAX_CHARS * 2)
        { host: host, url: @fetcher.utf8(search_url), text: text }
      rescue JSON::ParserError
        { error: 'dúchas search API returned unreadable JSON' }
      end

      # One search hit → its title, citable /en/cbes/<chapter>/<page>/<transcript> URL, and
      # transcript text (match highlighting stripped). The URL is logged so it can be cited.
      def entry(hit)
        story_url = "https://www.duchas.ie/en/cbes/#{hit['chapterID']}/#{hit['pageID']}/#{hit['id']}"
        @fetcher.log!('duchas.ie', story_url)
        snippet = hit['text'].to_s.gsub(%r{</?span[^>]*>}i, '').gsub(/\s+/, ' ').strip.first(SNIPPET)
        "#{hit['title']} — #{story_url}\n#{snippet}"
      end

      # A story page → its clean XML transcript endpoint (open data): the /en/ HTML story is
      # chrome-heavy, the /xml/ one is just the transcribed text. Only story pages (a numeric id
      # after /cbes/), never a search page.
      def xml_url(url)
        return url unless url.match?(STORY)

        url.sub('/en/cbes/', '/xml/cbes/')
      end

      # The dúchas XML holds one or more <transcript> elements (a page can carry several
      # stories); return them all. A single ENTRY can span pages, so surface each <story> URL
      # (the entry endpoint, which returns the whole story) as human /en/ links.
      def extract_xml(xml)
        doc = Nokogiri::XML(xml)
        transcripts = doc.css('transcript').filter_map { |t| t.text.gsub(/\s+/, ' ').strip.presence }.
                      join("\n\n").first(SourceFetcher::MAX_CHARS)

        entries = doc.css('story[url]').filter_map { |s| s['url']&.sub('/xml/cbes/', '/en/cbes/') }.uniq
        return transcripts if entries.empty?

        "#{transcripts}\n\nENTRIES (fetch one for the whole story):\n#{entries.join("\n")}"
      end
    end
  end
end
