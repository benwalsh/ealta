require 'rails_helper'

RSpec.describe BirdLore do
  def stub_lore(data)
    allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(data)
  end

  describe '.entries' do
    it 'wraps a single-entry hash in an array' do
      entry = { 'kind' => 'poem', 'text' => 'x', 'attribution' => 'y' }
      stub_lore({ 'Passer domesticus' => entry })

      expect(described_class.entries('Passer domesticus')).to eq([entry])
    end

    it 'returns a list of entries as-is, so a bird can hold several' do
      a = { 'kind' => 'poem', 'title' => 'A', 'text' => 'aa' }
      b = { 'kind' => 'poem', 'title' => 'B', 'text' => 'bb' }
      stub_lore({ 'Passer domesticus' => [a, b] })

      expect(described_class.entries('Passer domesticus')).to eq([a, b])
    end

    it 'returns [] for a species with no lore' do
      stub_lore({})

      expect(described_class.entries('Turdus merula')).to eq([])
    end
  end
end
