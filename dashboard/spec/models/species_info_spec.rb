require 'rails_helper'

RSpec.describe SpeciesInfo do
  describe '.english_for' do
    it 'returns a cached description without fetching' do
      described_class.create!(sci_name: 'Erithacus rubecula', description: 'Cached prose.')
      expect(described_class).not_to receive(:fetch)

      expect(described_class.english_for('Erithacus rubecula')).to eq('Cached prose.')
    end

    it 'fetches once, then caches for subsequent calls' do
      # No LLM configured (the default in test): describe() uses the raw first-paragraph fetch.
      # .once fails the spec if the cache miss isn't honoured on the second call.
      expect(described_class).to receive(:fetch).once.and_return('Fresh prose.')

      expect(described_class.english_for('Turdus merula', 'Common Blackbird')).to eq('Fresh prose.')
      expect(described_class.find_by(sci_name: 'Turdus merula').description).to eq('Fresh prose.')
      expect(described_class.english_for('Turdus merula')).to eq('Fresh prose.')
    end

    context 'with an LLM configured' do
      before { allow(Bedrock).to receive(:available?).and_return(true) }

      it 'summarises the fuller Wikipedia lead instead of storing the raw first paragraph' do
        allow(described_class).to receive(:fetch_lead).with('Pluvialis apricaria').
          and_return('The European golden plover, also known as the Eurasian golden plover… ' \
                     'It breeds on tundra and moorland and gathers in large winter flocks on farmland.')
        allow(Bedrock).to receive(:converse).and_return(
          'A tundra-breeding wader that gathers in big flocks on winter farmland.'
        )
        expect(described_class).not_to receive(:fetch) # the raw first-paragraph path is skipped

        expect(described_class.english_for('Pluvialis apricaria', 'European Golden Plover')).
          to eq('A tundra-breeding wader that gathers in big flocks on winter farmland.')
      end

      it 'falls back to the raw first paragraph when the summary is empty or fails' do
        allow(described_class).to receive(:fetch_lead).and_return('Some article text.')
        allow(Bedrock).to receive(:converse).and_raise(StandardError, 'model down')
        expect(described_class).to receive(:fetch).and_return('The raw first paragraph.')

        expect(described_class.english_for('Turdus merula', 'Common Blackbird')).
          to eq('The raw first paragraph.')
      end
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
