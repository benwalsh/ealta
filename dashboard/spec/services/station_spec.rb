require 'rails_helper'

RSpec.describe Station do
  # The sample profile offers [ga, en] with an Irish default and a configured url — so these
  # assert the config-driven mechanism, not any one station's identity.
  context 'with a bilingual station (sample profile)' do
    around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

    describe '.language' do
      it 'defaults to the configured default_language' do
        expect(described_class.language).to eq(:ga)
      end

      it 'reads the admin-set value from Setting' do
        described_class.language = :en
        expect(described_class.language).to eq(:en)
      end

      it 'rejects a language the station does not offer' do
        expect { described_class.language = :fr }.to raise_error(ArgumentError)
      end

      it 'falls back safely if a bad value somehow lands in the store' do
        Setting.set(Station::LANGUAGE_SETTING, 'martian')
        expect(described_class.language).to eq(:ga)
      end
    end

    it 'reports itself multilingual and reads its url from config' do
      expect(described_class.multilingual?).to be(true)
      expect(described_class.languages).to eq(%i[ga en])
      expect(described_class.url).to eq('example.test')
    end
  end

  context 'with the shipped example profile (English-only)' do
    it 'offers one language, is not multilingual, and never rejects the default' do
      expect(described_class.languages).to eq(%i[en])
      expect(described_class.multilingual?).to be(false)
      expect(described_class.language).to eq(:en)
    end
  end
end
