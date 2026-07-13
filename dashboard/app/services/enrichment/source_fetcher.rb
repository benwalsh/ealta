require 'net/http'
require 'uri'

module Enrichment
  # The fetch tool Stage 1 (Claude, via Bedrock tool-use) calls to source from trusted hosts —
  # the ONLY path the enrichment pass takes to the network. It:
  #   - refuses any host off the station’s trusted allowlist (sources.yml) — returns
  #     an error, makes no request;
  #   - routes a trusted URL a bespoke adapter claims (e.g. dúchas) to that adapter, else
  #     fetches and Nokogiri-strips the page itself;
  #   - logs every real outbound hit to source_fetch_log (the politeness ledger).
  # A URL the model wants but can't be trusted is refused, not fetched — the block that would
  # have needed it is simply dropped upstream. Never raises out; returns an error hash.
  class SourceFetcher
    MAX_CHARS = 4000
    MAX_LINKS = 30 # on-site links appended so the model can navigate a search/index page
    USER_AGENT = 'ealta/1.0 (bird detector; enrichment)'.freeze
    # Some trusted hosts answer a 301 before serving a page, so we MUST follow redirects or
    # they always read as "fetch failed". Bounded, and every hop is re-checked against the
    # allowlist so a redirect can't smuggle the fetch off to an untrusted host.
    MAX_REDIRECTS = 4

    delegate :trusted?, to: :@sources

    class << self
      # Host straight off the string — robust to un-encoded query chars (e.g. a fada in a
      # search term), where URI.parse would choke and wrongly read as untrusted. A pure
      # function so adapters can share it without an allowlist-less connection of their own.
      def host_of(url)
        url.to_s[%r{\Ahttps?://([^/?#]+)}i, 1]&.downcase
      end
    end

    def initialize(sci_name:, run_id:)
      @sci_name = sci_name
      @run_id = run_id
      @sources = SourceList.current
      @adapters = AdapterRegistry.enabled(@sources.adapters, self)
    end

    # { host:, url:, text: } on success, or { error: } — never raises. A trusted URL an enabled
    # adapter claims is handled by that adapter; anything else is fetched and stripped here.
    def fetch(url)
      host = SourceFetcher.host_of(url)
      return { error: "untrusted host: #{host}" } unless trusted?(host)

      adapter = @adapters.find { |a| a.matches?(url) }
      return adapter.fetch(url, host) if adapter

      body = http_get(url)
      return { error: "fetch failed: #{url}" } unless body

      log!(host, url)
      { host: host, url: utf8(url), text: extract_text(body, url) }
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    # --- Public for enabled adapters: the allowlist-checked HTTP and the shared helpers an
    # adapter needs, so a source adapter never opens its own uncontrolled connection. ---

    def http_get(url, redirects_left: MAX_REDIRECTS)
      uri = request_uri(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                            open_timeout: 5, read_timeout: 12) do |http|
        http.get(uri.request_uri, 'User-Agent' => USER_AGENT)
      end

      case res
      # Net::HTTP hands back ASCII-8BIT; the trusted hosts serve UTF-8 (fadas on Vicipéid/
      # dúchas), so tag it UTF-8 or the text breaks on the way into the DB.
      when Net::HTTPSuccess then res.body&.dup&.force_encoding(Encoding::UTF_8)
      when Net::HTTPRedirection then follow(res['location'], uri, redirects_left)
      end
    end

    # Generic readable text from an HTML page: scripts/chrome stripped, trusted on-site links
    # appended so the model can navigate a search or index page through to the actual entry.
    def extract_text(body, base_url)
      doc = Nokogiri::HTML(body)
      doc.search('script, style, nav, header, footer').remove
      text = doc.text.gsub(/\s+/, ' ').strip.first(MAX_CHARS)
      links = onsite_links(doc, base_url)
      links.empty? ? text : "#{text}\n\nLINKS (fetch one to read the full entry):\n#{links.join("\n")}"
    end

    def log!(host, url)
      # A seeded Vicipéid URL can arrive tagged ASCII-8BIT (its fada bytes); normalise to UTF-8
      # so the insert doesn't blow up on the citation string.
      SourceFetchLog.create!(host: host, url: utf8(url), sci_name: @sci_name,
                             fetched_at: Time.current, run_id: @run_id)
    end

    def utf8(str)
      str.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    private

    # A URI to fetch, even when the URL carries non-ASCII (a fada in a Vicipéid title) — try it
    # raw, then percent-encode just the non-ASCII bytes and retry. Only those bytes are touched,
    # so an already-encoded URL is never double-encoded.
    def request_uri(url)
      URI(url)
    rescue URI::InvalidURIError
      URI(url.to_s.gsub(/[^\x00-\x7F]/) { |c| c.bytes.map { |b| format('%%%02X', b) }.join })
    end

    # Follow a redirect only to another TRUSTED host (a redirect must never be a way off the
    # allowlist), resolving relative Location headers against the current URL.
    def follow(location, base, redirects_left)
      return nil if location.blank? || redirects_left <= 0

      target = URI.join(base, location)
      return nil unless trusted?(target.host&.downcase)

      http_get(target.to_s, redirects_left: redirects_left - 1)
    rescue URI::InvalidURIError
      nil
    end

    # Trusted, on-host links found in the content, absolutised and de-duped — so the model can
    # navigate a search or index page to the actual entry. Capped so they never crowd the text.
    def onsite_links(doc, base_url)
      base = safe_uri(base_url)
      return [] unless base

      doc.css('a[href]').filter_map do |a|
        next if a.text.strip.empty?

        target = safe_join(base, a['href'])
        host = SourceFetcher.host_of(target)
        next if target.nil? || host.nil? || !trusted?(host) || target == base_url

        target
      end.uniq.first(MAX_LINKS)
    end

    def safe_uri(url)
      URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end

    def safe_join(base, href)
      URI.join(base, href).to_s
    rescue URI::InvalidURIError, ArgumentError
      nil
    end
  end
end
