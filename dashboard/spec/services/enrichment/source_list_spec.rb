require 'rails_helper'

RSpec.describe Enrichment::SourceList do
  describe '.current (from the active profile)' do
    it 'trusts the hosts and affiliate pattern the sample profile configures' do
      with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) do
        list = described_class.current
        expect(list.trusted?('duchas.ie')).to be(true)
        expect(list.trusted?('birdwatchgalway.org')).to be(true) # affiliate pattern
        expect(list.trusted?('example.com')).to be(false)
        expect(list.adapters).to include('duchas')
      end
    end

    it 'trusts only Wikipedia and enables no adapters on the shipped example profile' do
      list = described_class.current # STATION_PROFILE unset → example
      expect(list.trusted?('en.wikipedia.org')).to be(true)
      expect(list.trusted?('duchas.ie')).to be(false)
      expect(list.adapters).to eq([])
    end
  end

  describe '#trusted?' do
    it 'is false for a blank host and never matches a look-alike' do
      list = described_class.new('trusted_hosts'     => ['duchas.ie'],
                                 'affiliate_pattern' => '\Abirdwatch[a-z]+\.(?:ie|org)\z')
      expect(list.trusted?(nil)).to be(false)
      expect(list.trusted?('')).to be(false)
      expect(list.trusted?('evil-duchas.ie.attacker.com')).to be(false)
    end
  end
end
