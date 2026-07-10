require 'rails_helper'

RSpec.describe StationProfile do
  describe 'per-file fallback to the shipped example' do
    it 'reads a file from the active profile when it overrides one' do
      with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) do
        expect(described_class.yaml('content/feilire.yml')).to have_key('07-07')
      end
    end

    it 'falls back to stations/example for a file the profile does not ship' do
      with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) do
        # the sample profile ships no prompts/ dir, so read() must fall through to the example
        expect(described_class.read('image/prompt.template.md')).to be_present
      end
    end

    it 'uses the example profile when STATION_PROFILE is unset' do
      expect(described_class.dir).to eq(described_class.example_dir)
    end

    it 'returns {} for an absent YAML file rather than raising' do
      expect(described_class.yaml('content/does_not_exist.yml')).to eq({})
    end
  end

  describe '.config' do
    it 'reads the active profile station.yml' do
      with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) do
        expect(described_class.config['place']).to include('en' => 'Sampleton')
      end
    end
  end
end
