require 'rails_helper'

RSpec.describe PlaceLore do
  def stub_lore(data)
    allow(StationProfile).to receive(:yaml).with('content/place_lore.yml').and_return(data)
  end

  describe '.for' do
    it 'returns nil when the station ships no core place-lore' do
      stub_lore({})
      expect(described_class.for(Date.new(2026, 7, 20))).to be_nil
    end

    it 'features a core-zone story, stable per date, with a composed credit' do
      stub_lore(
        'Ravenrock' => { 'zone' => 'core', 'entries' => [
          { 'kind' => 'description', 'title' => 'Ravenrock Falls', 'text' => 'The river falls…',
            'attribution' => "Roderic O'Flaherty", 'source_work' => 'A Chorographical Description',
            'year' => 1846 }
        ] }
      )
      out = described_class.for(Date.new(2026, 2, 1))

      expect(out).to include(place: 'Ravenrock', title: 'Ravenrock Falls')
      expect(out[:credit]).to eq("Roderic O'Flaherty · A Chorographical Description (1846)")
      expect(described_class.for(Date.new(2026, 2, 1))).to eq(out) # stable for the same date
    end

    it 'never reaches past the core zone (no near/wider/distant drift)' do
      stub_lore(
        'Ravenrock' => { 'zone' => 'core', 'entries' => [{ 'title' => 'Core' }] },
        'Cong'      => { 'zone' => 'distant', 'entries' => [{ 'title' => 'Distant' }] }
      )
      titles = (0..40).map { |i| described_class.for(Date.new(2026, 1, 1) + i)[:title] }.uniq

      expect(titles).to eq(['Core'])
    end

    it 'drops the disambiguating parenthetical from the heading' do
      stub_lore('This Coast (weather and sea)' => { 'zone'    => 'core',
                                                    'entries' => [{ 'title' => 'The Rainbows' }] })
      expect(described_class.for(Date.new(2026, 3, 1))[:place]).to eq('This Coast')
    end
  end
end
