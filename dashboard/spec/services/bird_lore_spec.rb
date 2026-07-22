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

    it 'surfaces a shared "multi:" excerpt under every species it tags' do
      shared = { 'kind' => 'legend', 'title' => 'The Crane in the Marshes',
                 'species' => ['Ardea cinerea', 'Grus grus'], 'text' => 'Sweet-voiced is the crane…' }
      stub_lore({ 'multi:corr-marsh' => [shared] })

      expect(described_class.entries('Ardea cinerea')).to eq([shared])
      expect(described_class.entries('Grus grus')).to eq([shared])
      expect(described_class.entries('Passer domesticus')).to eq([]) # not tagged
    end

    it 'appends shared excerpts after the bird\'s own entries, ordered by key' do
      own = { 'kind' => 'poem', 'title' => 'Own', 'text' => 'mine' }
      z = { 'kind' => 'poem', 'title' => 'Z', 'species' => ['Grus grus'], 'text' => 'z' }
      a = { 'kind' => 'poem', 'title' => 'A', 'species' => ['Grus grus'], 'text' => 'a' }
      stub_lore({ 'Grus grus' => own, 'multi:zzz' => [z], 'multi:aaa' => [a] })

      expect(described_class.entries('Grus grus')).to eq([own, a, z]) # own first, then aaa, then zzz
    end
  end
end
