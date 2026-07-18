require 'rails_helper'

RSpec.describe Enrichment::SeedLore do
  def stub_lore(data)
    allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(data)
  end

  describe '.blocks_for' do
    it 'turns each seed entry into a valid gated folklore block, credited by its attribution' do
      stub_lore('Passer domesticus' => [
                  { 'kind' => 'poem', 'text' => 'To a Sparrow.', 'attribution' => 'A poet' },
                  { 'kind' => 'tale', 'text' => 'The sparrow and the king.', 'attribution' => 'A folk tale' }
                ])

      blocks = described_class.blocks_for('Passer domesticus')

      expect(blocks.map(&:type)).to eq(%w[folklore folklore])
      expect(blocks).to all(be_valid)
      expect(blocks).to all(be_gated)
      expect(blocks.map(&:text)).to eq(['To a Sparrow.', 'The sparrow and the king.'])
      expect(blocks.map { |b| b.sources.first[:host] }).to eq(['A poet', 'A folk tale'])
      expect(blocks.map(&:id).uniq.size).to eq(2) # stable, distinct ids
    end

    it 'carries an Irish rendering through when the entry supplies one' do
      stub_lore('Turdus merula' => { 'kind' => 'poem', 'text' => 'Blackbird.', 'text_ga' => 'Lon dubh.',
                                     'attribution' => 'x' })

      expect(described_class.blocks_for('Turdus merula').first.text_ga).to eq('Lon dubh.')
    end

    it 'falls back to a station-curation credit when an entry has no attribution' do
      stub_lore('Turdus merula' => { 'kind' => 'poem', 'text' => 'Blackbird.' })

      expect(described_class.blocks_for('Turdus merula').first.sources.first[:host]).to eq('Station curation')
    end

    it 'skips blank entries and returns [] for a species with none' do
      stub_lore('Turdus merula' => { 'kind' => 'poem', 'text' => '  ', 'attribution' => 'x' })

      expect(described_class.blocks_for('Turdus merula')).to eq([])
      expect(described_class.blocks_for('Erithacus rubecula')).to eq([])
    end

    it 'credits a dúchas entry to the Schools\' Collection\'s required terms' do
      stub_lore('Erithacus rubecula' => {
                  'kind'   => 'lore',
                  'text'   => 'If a robin came to your house and was friendly with you there would be snow.',
                  'duchas' => {
                    'volume' => '0199', 'page' => '012',
                    'url' => 'https://www.duchas.ie/en/cbes/4602757/4601680/4633452',
                    'collector' => 'Ethel Gillmor', 'school' => 'Drom Dhá Eithear, Dromahair, Co. Leitrim'
                  }
                })

      src = described_class.blocks_for('Erithacus rubecula').first.sources.first

      expect(src[:host]).to eq("The Schools' Collection, Volume 0199, Page 012")
      expect(src[:url]).to eq('https://www.duchas.ie/en/cbes/4602757/4601680/4633452')
      expect(src[:holder]).to eq('© National Folklore Collection, UCD')
      expect(src[:licence]).to eq('CC BY-NC 4.0')
      expect(src[:licence_url]).to eq('https://creativecommons.org/licenses/by-nc/4.0/')
      expect(src[:collector]).to eq('Ethel Gillmor')
    end
  end
end
