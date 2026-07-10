require 'securerandom'

module Enrichment
  # Stage 1 of the enrichment pipeline: the SOURCING pass. For a notable species it
  # runs Claude (Bedrock Converse tool-use) with exactly one tool — SourceFetcher —
  # and asks it to read trusted ornithological / heritage pages and return a short set
  # of typed, cited blocks (a general fact, a regional note, a piece of folklore). The
  # result is stored once per (sci_name, date) as an EnrichmentBundle, so a single
  # lookup serves every subscriber's Assembler.
  #
  # Integrity is enforced, not trusted: a block survives only if it validates AND every
  # citation it carries was a URL we actually fetched this run (logged in
  # source_fetch_log). A fabricated citation is dropped; a block left with none is
  # dropped with it. "Ruby computes, Claude sources, and nothing unsourced ships."
  class Builder
    # Navigating the dúchas search → story pages costs fetches, so the loop needs headroom
    # to do that AND still secure a folklore block (falling back to Wikipedia) — 8 left it
    # exhausting the budget on the archives and finalising with none.
    MAX_ROUNDS = 12
    MAX_FETCH_CHARS = 6000
    # On a day with nothing notable, still source this many of the most interesting DUE
    # species — the floor that keeps a quiet/young station building a facts & folklore
    # library instead of sourcing nothing. 0 restores the old notable-only behaviour.
    DAILY_FLOOR = Integer(ENV.fetch('ENRICH_DAILY_FLOOR', 1))
    # When research runs long, this forces the model to stop and answer from what it has
    # already fetched, so a thorough explorer still yields blocks instead of nothing.
    FINALISE = 'Stop searching now. Using ONLY the sources you have already fetched ' \
               'successfully, output the JSON array of blocks and nothing else. Include a ' \
               'folklore block if any source you fetched supports one (e.g. a Wikipedia ' \
               'mythology/folklore section) — do not omit folklore just because the Irish ' \
               'archives were thin.'.freeze

    FETCH_TOOL = {
      tool_spec: {
        name:         'fetch_source',
        description:  'Fetch the readable text of a page on a trusted ornithological or ' \
                      'Irish-heritage host (e.g. en.wikipedia.org, birdwatchireland.ie, ' \
                      'duchas.ie). Returns plain text to read and cite, or an error if the ' \
                      'host is not trusted or the page cannot be read. This is the only way ' \
                      'to see a source; never cite a URL you have not fetched here.',
        input_schema: { json: {
          type:       'object',
          properties: { url: { type: 'string', description: 'Full https:// URL on a trusted host.' } },
          required:   ['url']
        } }
      }
    }.freeze

    class << self
      # The last exception the model call raised (or nil) — so a caller can explain WHY
      # a run produced nothing (e.g. the Bedrock Anthropic use-case form isn't submitted)
      # rather than silently returning empty.
      attr_reader :last_error

      # Build (and store) bundles for the day's notable species that are DUE a refresh
      # under the importance-keyed backoff (Enrichment::Policy) — so a bird already
      # sourced recently isn't re-researched until its facts are worth revisiting.
      # `only:` forces one species regardless of backoff (manual/on-demand sourcing).
      # Returns the bundles produced (nil results filtered out).
      def run(date: Date.current, only: nil)
        return [build_one(date: date, **only.symbolize_keys)].compact if only

        facts = DailyFacts.for(date: date)
        due_species(facts, date).filter_map { |sp| build_one(date: date, **sp.symbolize_keys) }
      end

      # Today's species to source: every notable one that's due under the backoff — or,
      # when nothing notable is due, a small FLOOR of the day's most interesting species
      # that still lack facts & folklore. Without the floor an ordinary (or young) station,
      # where nothing clears the notable bar, would source nothing for ever; with it the
      # station builds a library a bird at a time (durable + backoff mean each is sourced
      # once, then left alone) and always has something to show.
      def due_species(facts, date)
        items = facts.fetch(:items, [])
        importance = items.to_h { |i| [i[:sci_name], i[:importance]] }
        due = ->(sci) { Policy.due?(sci, importance[sci].to_i, as_of: date) }

        notable = EnrichmentGate.species_for(facts).select { |sp| due.call(sp[:sci_name]) }
        return notable if notable.any?

        items.select { |i| due.call(i[:sci_name]) }.
          first(DAILY_FLOOR).map { |i| i.slice(:sci_name, :common_name, :irish_name) }
      end

      # One species → one stored bundle, or nil when nothing survived validation.
      def build_one(date:, sci_name:, common_name: nil, irish_name: nil)
        name = BirdName.lookup(sci_name)
        blocks = source_blocks(sci_name: sci_name, common_name: common_name || name.en)
        return nil if blocks.empty?

        bundle = EnrichmentBundle.find_or_initialize_by(sci_name: sci_name, date: date)
        bundle.update!(
          common_name: common_name || name.en,
          irish_name:  irish_name || name.ga,
          blocks:      blocks.map(&:to_h)
        )
        bundle
      end

      private

      def gate_species(date)
        EnrichmentGate.species_for(DailyFacts.for(date: date))
      end

      # Run the tool-use loop and return the surviving validated Blocks.
      def source_blocks(sci_name:, common_name:)
        @last_error = nil
        run_id = SecureRandom.uuid
        fetcher = SourceFetcher.new(sci_name: sci_name, run_id: run_id)
        final = converse_loop(sci_name: sci_name, common_name: common_name, fetcher: fetcher)
        fetched = SourceFetchLog.where(run_id: run_id).pluck(:url).to_set
        parse_blocks(final).filter_map { |raw| vet(raw, fetched) }
      rescue StandardError => e
        @last_error = e
        Rails.logger.warn("Enrichment::Builder: #{sci_name} failed (#{e.class}: #{e.message})")
        []
      end

      def converse_loop(sci_name:, common_name:, fetcher:)
        system = format(Prompts.get('enrichment.system'), place: station_place)
        messages = [{ role: 'user', content: [{ text: task_message(sci_name, common_name) }] }]

        MAX_ROUNDS.times do
          resp = Bedrock.converse_tools(system: system, messages: messages, tools: [FETCH_TOOL])
          message = resp.output.message
          messages << { role: 'assistant', content: echo(message.content) }

          uses = message.content.select(&:tool_use)
          return text_of(message.content) if resp.stop_reason != 'tool_use' || uses.empty?

          messages << { role: 'user', content: uses.map { |c| tool_result(c, fetcher) } }
        end

        # Still researching at the round cap — make it answer now from what it has.
        messages << { role: 'user', content: [{ text: FINALISE }] }
        resp = Bedrock.converse_tools(system: system, messages: messages, tools: [FETCH_TOOL])
        text_of(resp.output.message.content)
      end

      # The opening task: the species and its Irish name — the name is given so the model's
      # text_ga translations use the correct Irish name; the content is sourced from English
      # Wikipedia and translated, never scraped from (sparse) Irish Wikipedia.
      def task_message(sci_name, common_name)
        irish = BirdName.lookup(sci_name).ga
        named = irish.present? ? "#{common_name} / #{irish}" : common_name
        "Species: #{named} (#{sci_name})."
      end

      # Re-shape response content structs back into request-shape content hashes so the
      # assistant turn can be echoed into the next request.
      def echo(content)
        content.filter_map do |c|
          if c.tool_use
            { tool_use: { tool_use_id: c.tool_use.tool_use_id, name: c.tool_use.name, input: c.tool_use.input } }
          elsif c.text.present?
            { text: c.text }
          end
        end
      end

      def tool_result(content, fetcher)
        input = content.tool_use.input || {}
        url = input['url'] || input[:url]
        out = fetcher.fetch(url)
        text = out[:error] ? "ERROR: #{out[:error]}" : out[:text].to_s.first(MAX_FETCH_CHARS)
        { tool_result: { tool_use_id: content.tool_use.tool_use_id,
                         content:     [{ text: text }],
                         status:      out[:error] ? 'error' : 'success' } }
      end

      def text_of(content)
        content.filter_map(&:text).join.strip
      end

      # Pull the JSON array out of the model's final turn (tolerate a stray code fence).
      def parse_blocks(text)
        json = text.to_s[/\[.*\]/m]
        json ? Array(JSON.parse(json)) : []
      rescue JSON::ParserError
        []
      end

      # A block survives only if, once its citations are cut to URLs we truly fetched,
      # it still validates (folklore gated, non-station types sourced, etc.).
      def vet(raw, fetched)
        return nil unless raw.is_a?(Hash)

        cited = Array(raw['sources'] || raw[:sources]).select { |s| fetched.include?(s['url'] || s[:url]) }
        block = Block.from(raw.merge('sources' => cited))
        block if block&.valid?
      end

      # The station's precise place (config-resolved, never hard-coded), which anchors
      # the local-connection block. Falls back to the country when nothing is configured.
      def station_place
        Station.region.presence || 'a location in Ireland'
      end
    end
  end
end
