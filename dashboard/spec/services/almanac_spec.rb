require 'rails_helper'
require 'tmpdir'

RSpec.describe Almanac do
  describe '.weather_from' do
    it 'maps a WMO code to bilingual labels + emoji and rounds the temperature' do
      expect(described_class.weather_from(9.4, 3)).to eq(temp: 9, text: 'overcast', text_ga: 'modartha', emoji: '☁️')
    end

    it 'degrades gracefully for an unknown code' do
      expect(described_class.weather_from(12.0, 999)).to eq(temp: 12, text: '—', text_ga: '—', emoji: '🌡️')
    end
  end

  describe '.sun_from' do
    it 'pulls today\'s sunrise/sunset as HH:MM' do
      daily = { 'sunrise' => ['2026-07-03T05:12'], 'sunset' => ['2026-07-03T21:45'] }
      expect(described_class.sun_from(daily)).to eq(rise: '05:12', set: '21:45')
    end

    it 'is nil without both times' do
      expect(described_class.sun_from(nil)).to be_nil
      expect(described_class.sun_from('sunrise' => ['2026-07-03T05:12'])).to be_nil
    end
  end

  describe '.next_tide' do
    # ERDDAP times are UTC; the label renders in Europe/Dublin (so 10:00Z → 11:00 IST).
    let(:extrema) do
      [{ t: '2026-07-07T10:00:00Z', type: 'low' },
       { t: '2026-07-07T16:45:00Z', type: 'high' }]
    end

    it 'returns the next upcoming turning point, in local time, bilingually' do
      tide = described_class.next_tide(extrema, Time.zone.parse('2026-07-07T08:00'),
                                       { en: 'Dublin Port', ga: 'Port Bhaile Átha Cliath' })
      expect(tide).to include(type: 'low', time: '11:00', station: 'Dublin Port',
                              label: 'Low tide 11:00 · Dublin Port',
                              label_ga: 'Lag trá 11:00 · Port Bhaile Átha Cliath')
    end

    it 'skips a turning point already passed and takes the next' do
      # read after the 11:00 low → the next is the 17:45 high
      tide = described_class.next_tide(extrema, Time.zone.parse('2026-07-07T13:00'))
      expect(tide).to include(type: 'high', time: '17:45')
    end

    it 'is nil when nothing is upcoming' do
      expect(described_class.next_tide(extrema, Time.zone.parse('2026-07-08T00:00'))).to be_nil
    end

    it 'shifts every prediction by offset_minutes (a local spot lagging its port)' do
      tide = described_class.next_tide(extrema, Time.zone.parse('2026-07-07T08:00'),
                                       { en: 'Back beach', ga: 'Trá beag' }, offset_minutes: 25)
      expect(tide).to include(type: 'low', time: '11:25', label: 'Low tide 11:25 · Back beach',
                              label_ga: 'Lag trá 11:25 · Trá beag')
    end
  end

  describe '.live_tide honouring station.yml tides:' do
    let(:data) do
      { tide_extrema: [{ t: '2026-07-07T10:00:00Z', type: 'low' }],
        tide_station: { en: 'Galway', ga: 'Gaillimh' } }
    end
    let(:now) { Time.zone.parse('2026-07-07T08:00') }

    it 'tides: none → no tide, even with cached predictions' do
      allow(Station).to receive(:setting).with('tides').and_return('none')
      expect(described_class.live_tide(data, now)).to be_nil
    end

    it 'tides: default (or unset) → the nearest station, unshifted' do
      allow(Station).to receive(:setting).with('tides').and_return(nil)
      expect(described_class.live_tide(data, now)).to include(time: '11:00', station: 'Galway')
    end

    it 'tides: offset + i18n → shifted time under the local name' do
      allow(Station).to receive(:setting).with('tides').
        and_return({ 'offset' => '25m', 'i18n' => { 'en' => 'Back beach', 'ga' => 'Trá beag' } })
      tide = described_class.live_tide(data, now)
      expect(tide).to include(time: '11:25', label: 'Low tide 11:25 · Back beach',
                              label_ga: 'Lag trá 11:25 · Trá beag')
    end
  end

  describe '.nearest_tide_station' do
    it 'picks Killary Harbour for a west-coast position' do
      # Killary is the closest Marine Institute station to this position
      expect(described_class.nearest_tide_station(53.62, -9.90)[:id]).to eq('Killary_Harbour')
    end

    it 'picks Dublin Port for a Dublin position' do
      expect(described_class.nearest_tide_station(53.334, -6.227)[:id]).to eq('Dublin_Port')
    end

    it 'picks Galway for the inner bay' do
      expect(described_class.nearest_tide_station(53.27, -9.05)[:id]).to eq('Galway')
    end
  end

  describe '.place_from' do
    it 'picks the most-local name and appends the county' do
      addr = { 'village' => 'Tullycross', 'county' => 'County Galway', 'city' => 'Galway' }
      expect(described_class.place_from(addr)).to eq('Tullycross, County Galway')
    end

    it 'does not repeat a name that is both locality and county' do
      expect(described_class.place_from('city' => 'Dublin', 'county' => 'Dublin')).to eq('Dublin')
    end

    it 'is nil when there is nothing usable' do
      expect(described_class.place_from(nil)).to be_nil
      expect(described_class.place_from({})).to be_nil
    end
  end

  describe '.current' do
    let(:dir) { Pathname(Dir.mktmpdir) }
    let(:file) { dir.join('almanac.json') }

    before { stub_const('Almanac::STORE', file) }

    after { FileUtils.remove_entry(dir) if dir.exist? }

    it 'returns a blank reading when the cache file is missing' do
      expect(file).not_to exist
      expect(described_class.current).to eq(coords: nil, weather: nil, sun: nil, tide: nil,
                                            tide_extrema: nil, tide_station: nil, fetched_at: nil)
    end

    it 'reads back a cached reading and parses fetched_at' do
      file.write({
        coords:     { lat: 53.5, lon: -9.9, place: 'Someplace' },
        weather:    { temp: 11, text: 'overcast', emoji: '☁️' },
        tide:       { type: 'high', time: '14:30', label: 'High 14:30' },
        fetched_at: '2026-07-03T08:00:00Z'
      }.to_json)
      reading = described_class.current
      expect(reading[:weather][:temp]).to eq(11)
      expect(reading[:coords][:place]).to eq('Someplace')
      expect(reading[:fetched_at]).to be_a(ActiveSupport::TimeWithZone)
    end

    it 'survives a corrupt cache file' do
      file.write('{ not json')
      expect(described_class.current).to eq(coords: nil, weather: nil, sun: nil, tide: nil,
                                            tide_extrema: nil, tide_station: nil, fetched_at: nil)
    end

    it 'derives the next tide LIVE from the cached predictions, tracking the current time' do
      # Read at 09:00 the next water is the 11:00 low; read at 13:00 (past it) the 17:45
      # high — same cache, no re-fetch: the read is time-aware. (ERDDAP times are UTC.)
      file.write({
        coords:       { lat: 1.0, lon: 1.0 },
        tide_extrema: [{ t: '2026-07-07T10:00:00Z', type: 'low' },
                       { t: '2026-07-07T16:45:00Z', type: 'high' }],
        tide_station: { en: 'Dublin Port', ga: 'Port Bhaile Átha Cliath' },
        fetched_at:   '2026-07-07T08:00:00Z'
      }.to_json)

      morning = described_class.current(now: Time.zone.parse('2026-07-07T09:00'))
      expect(morning[:tide]).to include(type: 'low', time: '11:00', station: 'Dublin Port')

      afternoon = described_class.current(now: Time.zone.parse('2026-07-07T13:00'))
      expect(afternoon[:tide]).to include(type: 'high', time: '17:45')
    end
  end
end
