require 'rails_helper'

RSpec.describe BirdLore do
  def stub_lore(data)
    allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(data)
  end

  it 'returns a single-entry hash as-is' do
    entry = { 'kind' => 'poem', 'text' => 'x', 'attribution' => 'y' }
    stub_lore({ 'Passer domesticus' => entry })

    expect(described_class.for('Passer domesticus')).to eq(entry)
  end

  it 'returns nil for a species with no lore' do
    stub_lore({})

    expect(described_class.for('Turdus merula')).to be_nil
  end

  context 'with a list of entries for one species' do
    let(:a) { { 'kind' => 'poem', 'title' => 'A', 'text' => 'aa' } }
    let(:b) { { 'kind' => 'poem', 'title' => 'B', 'text' => 'bb' } }

    before { stub_lore({ 'Passer domesticus' => [a, b] }) }

    it 'returns a single entry from the list, never the list itself' do
      expect([a, b]).to include(described_class.for('Passer domesticus'))
    end

    it 'is stable within a day' do
      day = Date.new(2026, 7, 11)
      first  = described_class.for('Passer domesticus', date: day)
      second = described_class.for('Passer domesticus', date: day)
      expect(first).to eq(second)
    end

    it 'rotates the choice across consecutive days' do
      day = Date.new(2026, 7, 11)
      expect(described_class.for('Passer domesticus', date: day)).
        not_to eq(described_class.for('Passer domesticus', date: day + 1))
    end

    it 'accepts a string date (the shape the journal passes)' do
      expect(described_class.for('Passer domesticus', date: '2026-07-11')).to be_a(Hash)
    end
  end
end
