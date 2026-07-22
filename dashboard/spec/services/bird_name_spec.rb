require 'rails_helper'

RSpec.describe BirdName do
  def stub_names(cfg)
    allow(StationProfile).to receive(:yaml).and_call_original
    allow(StationProfile).to receive(:yaml).with('content/bird_names.yml').and_return(cfg)
    described_class.reset!
  end

  after { described_class.reset! }

  describe '.lookup — the station English display overlay' do
    it 'passes the canonical label through when the station ships no overlay' do
      stub_names({})
      expect(described_class.lookup('Erithacus rubecula').en).to eq('European Robin')
    end

    it 'drops a configured leading prefix so the bare bird stands' do
      stub_names('strip_prefixes' => %w[Common European Eurasian])
      expect(described_class.lookup('Erithacus rubecula').en).to eq('Robin') # European
      expect(described_class.lookup('Pica pica').en).to eq('Magpie')         # Eurasian
      expect(described_class.lookup('Grus grus').en).to eq('Crane')          # Common
    end

    it 'lets an explicit override win over the label and the strip rule' do
      stub_names('strip_prefixes' => %w[Common], 'overrides' => { 'Motacilla alba' => 'Pied Wagtail' })
      expect(described_class.lookup('Motacilla alba').en).to eq('Pied Wagtail') # subspecies
    end

    it 'applies a spelling replacement (British Grey) after stripping' do
      stub_names('strip_prefixes' => %w[Common], 'replace' => [['\\AGray', 'Grey']])
      expect(described_class.lookup('Ardea cinerea').en).to eq('Grey Heron')     # Gray Heron
      expect(described_class.lookup('Motacilla cinerea').en).to eq('Grey Wagtail')
      expect(described_class.lookup('Anser anser').en).to eq('Greylag Goose')    # Graylag
    end

    it 'never strips a name down to nothing' do
      stub_names('strip_prefixes' => ['Robin'])
      expect(described_class.lookup('Erithacus rubecula').en).to eq('European Robin')
    end

    it 'still reports NO second name when the overlay changes English (the ga mirror bug)' do
      # Common Myna has no distinct Irish name — labels_ga.json mirrors the canonical English.
      # Stripping "Common" from the display English must NOT turn that mirror into a bogus second name.
      allow(Station).to receive(:languages).and_return(%w[en ga])
      stub_names('strip_prefixes' => %w[Common])
      name = described_class.lookup('Acridotheres tristis')
      expect(name.en).to eq('Myna')
      expect(name.ga).to be_nil
    end

    it 'keeps the second-language name from the locale file even when English is stripped' do
      # Grus grus's Irish "Grús" lives in labels_ga.json (a canonical correction, not a station
      # override); stripping "Common" from the English must not disturb it.
      allow(Station).to receive(:languages).and_return(%w[en ga])
      stub_names('strip_prefixes' => %w[Common])
      name = described_class.lookup('Grus grus')
      expect(name.en).to eq('Crane')
      expect(name.ga).to eq('Grús')
    end
  end
end
