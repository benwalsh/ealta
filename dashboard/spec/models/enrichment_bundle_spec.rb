require 'rails_helper'

RSpec.describe EnrichmentBundle do
  it 'is one bundle per species per date' do
    described_class.create!(sci_name: 'Cuculus canorus', date: Date.current, blocks: [])
    dup = described_class.new(sci_name: 'Cuculus canorus', date: Date.current, blocks: [])
    expect(dup).not_to be_valid
  end

  it 'allows the same species on a different date (folklore re-rolls daily)' do
    described_class.create!(sci_name: 'Cuculus canorus', date: Date.current, blocks: [])
    expect(described_class.new(sci_name: 'Cuculus canorus', date: Date.yesterday, blocks: [])).to be_valid
  end

  it 'hands the assembler only blocks that honour the contract' do
    bundle = described_class.create!(sci_name: 'Crex crex', date: Date.current, blocks: [
                                       { type: 'fact', id: 'ok', sources: [{ name: 'BWI', url: 'u' }] },
                                       { type: 'fact', id: 'bad', sources: [] } # dropped: unsourced
                                     ])
    expect(bundle.block_objects.map(&:id)).to eq(['ok'])
  end

  describe '.folklore_for' do
    around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

    it 'merges the station seed lore with the current bundle folklore, as one uniform list' do
      allow(StationProfile).to receive(:yaml).and_call_original
      allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(
        'Passer domesticus' => { 'kind' => 'poem', 'text' => 'A seed poem.', 'attribution' => 'a poet' }
      )
      described_class.create!(sci_name: 'Passer domesticus', date: Date.current, blocks: [
                                { type: 'fact', id: 'f', sources: [{ host: 'en.wikipedia.org', url: 'u' }] },
                                { type: 'folklore', id: 'd', gated: true, text: 'A dúchas passage.',
                                  sources: [{ host: 'duchas.ie', url: 'https://duchas.ie/1' }] }
                              ])

      blocks = described_class.folklore_for('Passer domesticus')

      # Seed first, then sourced — both folklore, the Wikipedia fact excluded entirely.
      expect(blocks.map(&:type)).to eq(%w[folklore folklore])
      expect(blocks.map(&:text)).to eq(['A seed poem.', 'A dúchas passage.'])
    end

    it 'returns the seed lore even when no bundle has been sourced yet' do
      allow(StationProfile).to receive(:yaml).and_call_original
      allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(
        'Passer domesticus' => { 'kind' => 'poem', 'text' => 'A seed poem.', 'attribution' => 'a poet' }
      )

      expect(described_class.folklore_for('Passer domesticus').map(&:text)).to eq(['A seed poem.'])
    end
  end

  describe '.display_for' do
    around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

    before do
      allow(StationProfile).to receive(:yaml).and_call_original
      allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(
        'Passer domesticus' => { 'kind' => 'poem', 'text' => 'A seed poem.', 'attribution' => 'a ninth-century poet' }
      )
    end

    it 'shows the seed folklore in the modal card even with no bundle, credited by attribution' do
      card = described_class.display_for('Passer domesticus')

      expect(card[:blocks].pluck(:type, :text)).to eq([['folklore', 'A seed poem.']])
      # a URL-less credit survives (the attribution), so the modal still says whence; nil fields
      # (url, and the dúchas-only holder/licence) are compacted away for a plain literary credit
      expect(card[:blocks].first[:sources]).to eq([{ host: 'a ninth-century poet' }])
    end

    it 'carries a dúchas seed citation to the card with its full rights metadata' do
      allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(
        'Erithacus rubecula' => {
          'kind' => 'lore', 'text' => 'A robin foretells snow.',
          'duchas' => { 'volume' => '0199', 'page' => '012',
                        'url' => 'https://www.duchas.ie/en/cbes/4602757/4601680/4633452',
                        'collector' => 'Ethel Gillmor' }
        }
      )

      src = described_class.display_for('Erithacus rubecula')[:blocks].first[:sources].first

      expect(src).to eq(host:        "The Schools' Collection, Volume 0199, Page 012",
                        url:         'https://www.duchas.ie/en/cbes/4602757/4601680/4633452',
                        holder:      '© National Folklore Collection, UCD',
                        licence:     'CC BY-NC 4.0',
                        licence_url: 'https://creativecommons.org/licenses/by-nc/4.0/',
                        collector:   'Ethel Gillmor')
    end

    it 'merges seed folklore after the sourced bundle blocks, one uniform card' do
      described_class.create!(sci_name: 'Passer domesticus', date: Date.current, blocks: [
                                { type: 'fact', id: 'f', text: 'Sparrows are gregarious.',
                                  sources: [{ host: 'en.wikipedia.org', url: 'u' }] }
                              ])

      rendered = described_class.display_for('Passer domesticus')[:blocks].pluck(:type, :text)
      expect(rendered).to eq([['fact', 'Sparrows are gregarious.'], ['folklore', 'A seed poem.']])
    end
  end
end
