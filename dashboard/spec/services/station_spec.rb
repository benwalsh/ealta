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

  describe '.setting (the Devise-style services config)' do
    before do
      allow(StationProfile).to receive(:config).and_return(
        'llm' => { 'region' => 'eu-west-1', 'enrich_daily_floor' => 2 }
      )
    end

    it 'resolves a dotted path from station.yml' do
      expect(described_class.setting('llm.region')).to eq('eu-west-1')
      expect(described_class.setting('llm.enrich_daily_floor')).to eq(2)
    end

    it 'falls back to the default when the option is not set (the commented-out state)' do
      expect(described_class.setting('llm.summary_model', default: 'nova')).to eq('nova')
      expect(described_class.setting('illustrations.base_url')).to be_nil
    end

    it 'lets the env override the profile (deploy pinning)' do
      original = ENV.fetch('BEDROCK_REGION', nil)
      ENV['BEDROCK_REGION'] = 'us-east-1'
      expect(described_class.setting('llm.region', env: 'BEDROCK_REGION')).to eq('us-east-1')
    ensure
      original ? ENV['BEDROCK_REGION'] = original : ENV.delete('BEDROCK_REGION')
    end
  end

  describe 'Bedrock.available? via the llm config' do
    it 'is on when station.yml has an llm block, off with none (and no env)' do
      allow(StationProfile).to receive(:config).and_return({ 'llm' => { 'region' => 'eu-west-1' } })
      expect(Bedrock.available?).to be(true)

      allow(StationProfile).to receive(:config).and_return({})
      expect(Bedrock.available?).to be(false)
    end
  end
end
