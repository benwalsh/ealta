require 'rails_helper'

RSpec.describe Feilire do
  # Assert the MECHANISM against a neutral sample profile — a curated day shows its entry, an
  # uncurated day falls back to its season. Real Irish feasts are a station overlay's
  # own content, tested in its own suite, not here in the open-source core.
  around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

  describe '.for' do
    it 'returns the curated entry for a day carrying one' do
      entry = described_class.for(Date.new(2026, 7, 7)) # sample profile: a curated feast
      expect(entry['kind']).to eq('saint')
      expect(entry['title']).to include('en' => "Founders' Day")
      expect(entry['gloss']['ga']).to be_present
    end

    it 'names the quarter-day at a cross-quarter date' do
      expect(described_class.for(Date.new(2026, 11, 1))['title']['en']).to eq('Turn of the Year')
    end

    it 'falls back to the Celtic season on an uncurated day (Celtic seasons, not solstices)' do
      entry = described_class.for(Date.new(2026, 6, 20)) # no curated entry → summer
      expect(entry['kind']).to eq('season')
      expect(entry['title']).to include('en' => 'Summer')
      expect(entry['season']).to eq('samhradh')
    end
  end
end
