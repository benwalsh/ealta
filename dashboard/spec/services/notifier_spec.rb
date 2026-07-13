require 'rails_helper'

RSpec.describe Notifier do
  describe '.deliver' do
    it 'is a no-op returning true when disabled' do
      allow(described_class).to receive(:enabled?).and_return(false)
      sub = create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      event = create(:event, event_type: 'species', sci_name: 'Crex crex')
      expect(described_class.deliver(event: event, subscription: sub)).to be(true)
    end

    it 'sends a single-bird alert as SES simple content (no stored template)' do
      ENV['ALERTS_FROM'] = 'alerts@example.com'
      sub = create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      event = create(:event, event_type: 'species', sci_name: 'Crex crex')
      fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
      allow(described_class).to receive(:client).and_return(fake)
      expect(fake).to receive(:send_email).with(hash_including(content: hash_including(:simple)))
      expect(described_class.deliver(event: event, subscription: sub)).to be(true)
    ensure
      ENV.delete('ALERTS_FROM')
    end
  end

  describe '.deliver_letter' do
    let(:date) { Date.new(2026, 7, 4) }
    let(:entry) do
      JournalEntry.new(
        date: date, source: 'facts',
        bullets: { 'en' => ['A corncrake called twice at dusk.'],
                   'ga' => ['Ghlaoigh traonach faoi dhó um thráthnóna.'] },
        sources: [{ 'host' => 'en.wikipedia.org', 'url' => 'https://en.wikipedia.org/wiki/Corn_crake' }]
      )
    end

    it 'is a no-op returning true when disabled' do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.deliver_letter(user: create(:user), date: date, entry: entry)).to be(true)
    end

    # aws-sdk-sesv2 lives in the :cloud gem group and isn't loaded in test, so the SES
    # client can't be a verifying double — plain doubles stand in (client is stubbed).
    context 'when enabled' do
      around do |example|
        ENV['ALERTS_FROM'] = 'alerts@example.com'
        example.run
        ENV.delete('ALERTS_FROM')
      end

      it 'sends the journal entry as a UTF-8 letter — both languages, sources, no encoding errors' do
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          text = args.dig(:content, :simple, :body, :text, :data)
          expect(text).to include('A corncrake called twice at dusk.')
          expect(text).to include('en.wikipedia.org')
          expect(text.encoding).to eq(Encoding::UTF_8)
        end
        expect(described_class.deliver_letter(user: create(:user), date: date, entry: entry)).to be(true)
      end

      it 'leads with Irish for an Irish-first station' do
        allow(Station).to receive_messages(default_language: :ga, multilingual?: true, languages: %i[ga en])
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          text = args.dig(:content, :simple, :body, :text, :data)
          expect(text.index('Ghlaoigh traonach')).to be < text.index('A corncrake called')
        end
        described_class.deliver_letter(user: create(:user), date: date, entry: entry)
      end
    end
  end
end
