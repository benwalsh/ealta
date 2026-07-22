require 'rails_helper'

RSpec.describe DayLore do
  def stub_lore(data)
    allow(StationProfile).to receive(:yaml).with('content/day_lore.yml').and_return(data)
  end

  describe '.easter' do
    it 'computes Easter Sunday (2026 → 5 April, 2027 → 28 March)' do
      expect(described_class.easter(2026)).to eq(Date.new(2026, 4, 5))
      expect(described_class.easter(2027)).to eq(Date.new(2027, 3, 28))
    end
  end

  describe '.for' do
    it 'returns nil for a day with no curated lore' do
      stub_lore({})
      expect(described_class.for(Date.new(2026, 7, 20))).to be_nil
    end

    it 'features a dated entry with a composed credit' do
      stub_lore('02-01' => [{ 'kind' => 'custom', 'title' => 'The First Day of Spring',
                              'text' => 'The ancient Irish divided the year…', 'note' => 'Imbolc.',
                              'attribution' => 'Collected by Lady Wilde',
                              'source_work' => 'Ancient Legends', 'year' => 1887 }])
      out = described_class.for(Date.new(2026, 2, 1))

      expect(out).to include(kind: 'custom', title: 'The First Day of Spring', note: 'Imbolc.')
      expect(out[:credit]).to eq('Collected by Lady Wilde · Ancient Legends (1887)')
    end

    it 'resolves a movable feast from Easter (Whitsuntide = Easter + 49 days)' do
      stub_lore('movable:whitsuntide' => [{ 'kind' => 'belief', 'title' => 'Beware of Water',
                                            'text' => 'Whitsuntide is a fatal time.' }])
      whit = described_class.easter(2026) + 49

      expect(described_class.for(whit)).to include(title: 'Beware of Water')
      expect(described_class.for(whit - 1)).to be_nil # only on the feast itself
    end
  end
end
