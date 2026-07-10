require 'rails_helper'

RSpec.describe SpeciesInfo do
  describe '.english_for' do
    it 'returns a cached description without fetching' do
      described_class.create!(sci_name: 'Erithacus rubecula', description: 'Cached prose.')
      expect(described_class).not_to receive(:fetch)

      expect(described_class.english_for('Erithacus rubecula')).to eq('Cached prose.')
    end

    it 'fetches once, then caches for subsequent calls' do
      # .once fails the spec if the cache miss isn't honoured on the second call.
      expect(described_class).to receive(:fetch).once.and_return('Fresh prose.')

      expect(described_class.english_for('Turdus merula', 'Common Blackbird')).to eq('Fresh prose.')
      expect(described_class.find_by(sci_name: 'Turdus merula').description).to eq('Fresh prose.')
      expect(described_class.english_for('Turdus merula')).to eq('Fresh prose.')
    end
  end

  describe '.irish_for' do
    before { allow(Bedrock).to receive(:disabled?).and_return(false) }

    it 'translates the richer English summary to Irish (not the sparse Irish article), and caches it' do
      described_class.create!(sci_name: 'Turdus merula', description: 'The blackbird is a common thrush.')
      allow(Bedrock).to receive(:converse).and_return('Is smólach coitianta é an lon dubh.')
      expect(described_class).not_to receive(:fetch) # ga.wikipedia is not touched when the translation works

      expect(described_class.irish_for('Turdus merula', 'Lon dubh')).to eq('Is smólach coitianta é an lon dubh.')
      # cached on the second call
      expect(described_class.irish_for('Turdus merula', 'Lon dubh')).to eq('Is smólach coitianta é an lon dubh.')
    end

    it 'falls back to the native Irish Wikipedia article when the model is unavailable' do
      described_class.create!(sci_name: 'Turdus merula', description: 'English prose.')
      allow(Bedrock).to receive(:disabled?).and_return(true)
      expect(described_class).to receive(:fetch).with('Lon dubh', 'ga').and_return('Gaeilge ó Vicipéid.')

      expect(described_class.irish_for('Turdus merula', 'Lon dubh')).to eq('Gaeilge ó Vicipéid.')
    end

    it 'remembers a miss (no English to translate, no Irish article) so it is not retried' do
      allow(described_class).to receive(:english_for).and_return(nil)
      allow(Bedrock).to receive(:disabled?).and_return(true)
      expect(described_class).to receive(:fetch).with('Lon dubh', 'ga').once.and_return(nil)

      expect(described_class.irish_for('Turdus merula', 'Lon dubh')).to be_nil
      expect(described_class.irish_for('Turdus merula', 'Lon dubh')).to be_nil # cached miss
    end
  end
end
