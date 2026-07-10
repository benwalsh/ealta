require 'rails_helper'

RSpec.describe Detection do
  describe '.within' do
    before { travel_to Time.zone.local(2026, 6, 29, 12, 0) }

    it 'excludes detections older than the window but keeps recent ones' do
      create(:detection, Date: Date.new(2026, 6, 29), Time: Time.zone.local(2026, 6, 29, 11, 30))
      create(:detection, Date: Date.new(2026, 6, 20), Time: Time.zone.local(2026, 6, 20, 11, 30))
      expect(described_class.within(24).count).to eq(1)
      expect(described_class.within(1_000_000).count).to eq(2)
    end
  end

  describe '.tally_within' do
    it 'returns one tally per species, loudest first' do
      travel_to Time.zone.local(2026, 6, 29, 12, 0)
      create(:detection, Sci_Name: 'Turdus merula', Com_Name: 'Eurasian Blackbird')
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
      tallies = described_class.tally_within(24)
      expect(tallies.map(&:sci_name)).to eq(['Erithacus rubecula', 'Turdus merula'])
      expect(tallies.first.count).to eq(2)
    end
  end

  describe 'credibility filtering' do
    it 'hides a lone low-confidence hit but keeps confident or repeated species' do
      create(:detection, Sci_Name: 'Mareca strepera', Com_Name: 'Gadwall', Confidence: 0.27)
      create(:detection, Sci_Name: 'Periparus ater', Com_Name: 'Coal Tit', Confidence: 0.72)
      create_list(:detection, 5, Sci_Name: 'Corvus cornix', Com_Name: 'Hooded Crow', Confidence: 0.35)

      names = described_class.tally_within(1_000_000).map(&:sci_name)
      expect(names).to include('Periparus ater', 'Corvus cornix') # confident / repeated
      expect(names).not_to include('Mareca strepera')             # lone + low confidence
    end
  end

  describe '.life_list' do
    it 'returns one entry per species with totals' do
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
      entry = described_class.life_list.find { |e| e.sci_name == 'Erithacus rubecula' }
      expect(entry.count).to eq(2)
    end
  end

  describe '#heard_at' do
    it 'combines the separate Date and Time columns into one moment' do
      detection = create(:detection, Date: Date.new(2026, 6, 29), Time: Time.zone.local(2000, 1, 1, 6, 14, 30))
      expect(detection.heard_at).to eq(Time.zone.local(2026, 6, 29, 6, 14, 30))
    end
  end

  describe '.by_period' do
    it 'labels every recency bucket' do
      expect(described_class.by_period.map(&:first)).to eq(['Past hour', 'Past 24 hours', 'Past 7 days', 'All time'])
    end
  end
end
