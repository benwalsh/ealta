module Enrichment
  # bird_lore.yml as a folklore SOURCE. A station's own curated poems and tales are folklore
  # exactly like a dúchas passage — sourced from the station's curation instead of a website — so
  # each entry becomes a folklore Block, the same typed, cited shape the web sourcing produces.
  # No model, no fetch: the curation IS the source, credited by its attribution. This is what lets
  # seed and web folklore be treated identically everywhere folklore is consumed (see
  # EnrichmentBundle.folklore_for). Wikipedia prose is a `fact`, never folklore, so it never
  # competes here.
  class SeedLore
    class << self
      # Every curated entry for a species as a folklore Block (type folklore, gated), in the order
      # authored. [] when the species has none, or an entry carries neither prose nor verse. The
      # station's curation is trusted content, so — unlike the web sourcing — these aren't
      # fetch-vetted; the attribution stands as the citation.
      #
      # A literary entry is richer than a scraped passage: it may have a title, an original-language
      # text, a set-apart verse `quote`, and a contextual `note`, with a proper book citation. Those
      # ride ALONGSIDE the block's plain fields (in extra attrs the contract ignores) so the journal's
      # Bird Lore & Wisdom block can render the whole thing, while the block still validates and pools
      # with web folklore exactly as before.
      def blocks_for(sci_name)
        BirdLore.entries(sci_name).each_with_index.filter_map do |entry, i|
          text  = entry['text'].to_s.strip
          quote = entry['quote'].to_s.strip
          next if text.blank? && quote.blank? # an entry has to carry SOMETHING to say

          block = Block.from(type: 'folklore', id: "seed-#{sci_name.parameterize}-#{i}", gated: true,
                             text: text, text_ga: entry['text_ga'].presence,
                             sources: [source_for(entry)],
                             lore_kind: entry['kind'].presence, title: entry['title'].presence,
                             quote: quote.presence, note: entry['note'].presence,
                             credit: credit_for(entry))
          block if block&.valid?
        end
      end

      private

      # A dúchas entry (nested `duchas:` block) is credited to the Schools' Collection's required
      # terms via DuchasCitation; any other entry keeps its plain literary attribution. Both are
      # just a source hash — indistinguishable to Block and everything downstream.
      def source_for(entry)
        d = entry['duchas']
        return { host: attribution(entry) } unless d.is_a?(Hash)

        DuchasCitation.source(url: d['url'], volume: d['volume'], page: d['page'],
                              collector: d['collector'], informant: d['informant'],
                              school: d['school'], collection: d['collection'])
      end

      def attribution(entry)
        entry['attribution'].to_s.strip.presence || 'Station curation'
      end

      # The reader-facing citation for a literary entry: the attribution (author/translator), then
      # the source work and year where held — "Ossianic lay, trans. Eleanor Hull · The Poem-book of
      # the Gael (1912)". nil for a bare dúchas-style entry (its LoreCredit carries the citation).
      def credit_for(entry)
        return nil if entry['duchas'].is_a?(Hash)

        work = entry['source_work'].to_s.strip.presence
        year = entry['year'] || entry['year_translation']
        tail = if work then year ? "#{work} (#{year})" : work
               elsif year then year.to_s
               end
        [attribution(entry), tail].compact.join(' · ').presence
      end
    end
  end
end
