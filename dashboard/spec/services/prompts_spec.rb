require 'rails_helper'

RSpec.describe Prompts do
  describe '.get' do
    it 'returns the named system prompt from the shipped example profile' do
      expect(described_class.get('day_note.system')).to include('bird-listening station')
    end

    it 'keeps the interpolation placeholder intact for the caller to fill' do
      expect(described_class.get('day_note.system')).to include('%<where>s')
    end

    it 'falls back to the example when the active profile ships no prompts of its own' do
      with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) do
        # the sample profile has no prompts/ dir, so this must resolve from stations/example
        expect(described_class.get('enrichment.system')).to include('%<place>s')
      end
    end

    it 'raises for a prompt neither the profile nor the example ships' do
      expect { described_class.get('nope.system') }.to raise_error(/no prompt file/)
    end
  end
end
