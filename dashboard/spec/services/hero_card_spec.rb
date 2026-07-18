require 'rails_helper'

RSpec.describe HeroCard do
  describe '.for' do
    before do
      allow(SpeciesInfo).to receive_messages(english_for: 'A wader of upland bogs.', irish_for: 'Éan portaigh.')
    end

    it 'returns nil without a hero' do
      expect(described_class.for(nil)).to be_nil
      expect(described_class.for('')).to be_nil
    end

    it 'is the sourced summary alone — the bundle\'s blocks are not listed on the card' do
      # fact / regional_note are what the day's NARRATION is written from (DayNarrator reads
      # them off the bundle), so printing them under that narration said the same things twice
      # in a flatter voice. Folklore was never here either — it is the set-apart coda quote.
      EnrichmentBundle.create!(
        sci_name: 'Pluvialis apricaria', date: Date.current,
        blocks: [{ type: 'fact', id: 'f', text: 'Breeds on moorland.',
                   sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/x' }] },
                 { type: 'regional_note', id: 'r', text: 'Winters on Irish estuaries.',
                   sources: [{ host: 'birdwatchireland.ie', url: 'https://birdwatchireland.ie/y' }] },
                 { type: 'folklore', id: 'l', gated: true, text: 'A plover omen.',
                   sources: [{ host: 'duchas.ie', url: 'https://duchas.ie/z' }] }]
      )

      card = described_class.for('Pluvialis apricaria')

      expect(card).to eq(sci: 'Pluvialis apricaria', en: card[:en], ga: card[:ga],
                         description: 'A wader of upland bogs.', description_ga: 'Éan portaigh.')
      expect(card).not_to have_key(:facts)
    end

    it 'reads the same with no bundle at all' do
      card = described_class.for('Pluvialis apricaria')
      expect(card[:description]).to eq('A wader of upland bogs.')
      expect(card).not_to have_key(:facts)
    end
  end
end
