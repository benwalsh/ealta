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

  # The photograph is FOR THE NEWSLETTER ONLY — the website stays on the station's own
  # dithered illustrations. These pin the licence gate rather than the happy path, because
  # that is where the risk is: showing an image we cannot license, or crediting the wrong
  # person, is a legal fault rather than a cosmetic one. Allowlist, and refuse when unsure —
  # a refusal just means the letter uses the illustration instead.
  describe 'newsletter photograph' do
    def meta(license:, restrictions: '', artist: 'A. Photographer', short: nil)
      { 'License'          => { 'value' => license },
        'Restrictions'     => { 'value' => restrictions },
        'LicenseShortName' => { 'value' => short || license.upcase },
        'Artist'           => { 'value' => artist } }
    end

    def licence_for(**args) = described_class.send(:licence_label, meta(**args))

    describe 'the licence allowlist' do
      it 'accepts the free licences we may reuse with attribution' do
        %w[cc0 cc-by-4.0 cc-by-sa-3.0 pd public-domain].each do |code|
          expect(licence_for(license: code)).to be_present, "expected #{code} to be allowed"
        end
      end

      it 'refuses non-commercial and no-derivatives licences' do
        # CC BY-NC / BY-ND look superficially like the licences above and are not reusable here.
        %w[cc-by-nc-4.0 cc-by-nc-sa-3.0 cc-by-nd-4.0].each do |code|
          expect(licence_for(license: code)).to be_nil, "expected #{code} to be refused"
        end
      end

      it 'refuses fair-use, non-free and unrecognised tags' do
        ['fair use', 'non-free', 'used with permission', '', 'nonsense'].each do |code|
          expect(licence_for(license: code)).to be_nil, "expected #{code.inspect} to be refused"
        end
      end

      it 'refuses an otherwise-free image carrying usage restrictions' do
        # Trademark or personality rights need a judgement an automated send cannot make.
        expect(licence_for(license: 'cc-by-sa-4.0', restrictions: 'trademarked')).to be_nil
      end
    end

    describe 'the credit line' do
      it 'names the photographer alongside the licence' do
        allow(described_class).to receive(:get_json).and_return(
          'query' => { 'pages' => { '1' => { 'imageinfo' => [
            { 'url'         => 'https://upload.wikimedia.org/robin.jpg',
              'extmetadata' => meta(license: 'cc-by-sa-3.0', artist: 'Francis C. Franklin',
                                    short: 'CC BY-SA 3.0') }
          ] } } }
        )
        expect(described_class.send(:photo_from_commons, 'File:robin.jpg')).
          to eq(url:    'https://upload.wikimedia.org/robin.jpg',
                credit: 'Francis C. Franklin · CC BY-SA 3.0')
      end

      it 'drops an image whose licence is refused, however good the photo' do
        allow(described_class).to receive(:get_json).and_return(
          'query' => { 'pages' => { '1' => { 'imageinfo' => [
            { 'url'         => 'https://upload.wikimedia.org/nope.jpg',
              'extmetadata' => meta(license: 'cc-by-nc-4.0') }
          ] } } }
        )
        expect(described_class.send(:photo_from_commons, 'File:nope.jpg')).to be_nil
      end

      it 'strips the HTML Commons wraps the artist in' do
        html = '<a href="//commons.wikimedia.org/wiki/User:Someone">Someone</a>'
        expect(described_class.send(:strip_markup, html)).to eq('Someone')
      end

      it 'treats a stored photo with no credit as no photo' do
        info = described_class.new(photo_url: 'https://example.org/x.jpg', photo_credit: nil)
        expect(described_class.send(:stored_photo, info)).to be_nil
      end

      it 'returns the stored pair when both parts are present' do
        info = described_class.new(photo_url: 'https://example.org/x.jpg', photo_credit: 'A · CC BY 4.0')
        expect(described_class.send(:stored_photo, info)).
          to eq(url: 'https://example.org/x.jpg', credit: 'A · CC BY 4.0')
      end
    end

    describe '.photo_for' do
      it 'records a miss so a species without a usable photo is not refetched every send' do
        # Exactly once across BOTH calls: the recorded attempt is what stops the second
        # send from going back to the network for a bird Commons has nothing usable for.
        expect(described_class).to receive(:fetch_photo).once.and_return(nil)

        expect(described_class.photo_for('Notabird notarealis')).to be_nil
        expect(described_class.find_by(sci_name: 'Notabird notarealis').fetched_photo_at).to be_present
        expect(described_class.photo_for('Notabird notarealis')).to be_nil
      end
    end
  end

  describe 'not freezing a fallback description' do
    # A description cached while the model was briefly unavailable used to stay the raw
    # Wikipedia lead forever — nomenclature trivia, never upgraded. Preparing content
    # automatically on detection would make that far easier to hit, so a failed summary
    # must leave nothing behind to retry against.
    before do
      allow(described_class).to receive_messages(fetch_lead: 'Some article text.',
                                                 fetch:      'Erithacus rubecula is a species of bird.')
    end

    it 'does not cache the lead paragraph when a model was available but failed' do
      allow(Bedrock).to receive(:available?).and_return(true)
      allow(described_class).to receive(:summarise).and_return(nil)

      text = described_class.english_for('Erithacus rubecula', 'European Robin')

      expect(text).to be_present # the caller still gets something to show
      expect(described_class.find_by(sci_name: 'Erithacus rubecula')&.description).to be_nil
    end

    it 'caches the summary when the model produces one' do
      allow(Bedrock).to receive(:available?).and_return(true)
      allow(described_class).to receive(:summarise).and_return('A small, round, red-breasted bird.')

      described_class.english_for('Erithacus rubecula', 'European Robin')

      expect(described_class.find_by(sci_name: 'Erithacus rubecula').description).
        to eq('A small, round, red-breasted bird.')
    end

    it 'caches the lead when no model is configured at all — then it IS the intended answer' do
      allow(Bedrock).to receive(:available?).and_return(false)

      described_class.english_for('Erithacus rubecula', 'European Robin')

      expect(described_class.find_by(sci_name: 'Erithacus rubecula').description).to be_present
    end
  end
end
