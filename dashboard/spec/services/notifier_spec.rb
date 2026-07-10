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

  describe '.deliver_digest' do
    let(:facts) do
      name = BirdName.lookup('Crex crex') # real UTF-8 Irish name (fada)
      DigestFacts::Result.new(
        date:    Date.new(2026, 7, 4),
        follows: [{ sci: 'Crex crex', en: name.en, ga: name.ga, count: 2 }],
        alerts:  [{ kind: 'rarity', sci: 'Anser anser', en: 'Greylag Goose', ga: 'Gé ghlas' }],
        roundup: { species_today: 28, detections_today: 340, activity_note: 'typical' }
      )
    end

    it 'is a no-op returning true when disabled' do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.deliver_digest(user: create(:user), date: Date.current, facts: facts)).to be(true)
    end

    # aws-sdk-sesv2 lives in the :cloud gem group and isn't loaded in test, so the SES
    # client can't be a verifying double — plain doubles stand in (client is stubbed).
    context 'when enabled' do
      around do |example|
        ENV['ALERTS_FROM'] = 'alerts@example.com'
        example.run
        ENV.delete('ALERTS_FROM')
      end

      it 'builds and sends a UTF-8 email with the narrated note (no encoding errors)' do
        allow(DigestSummary).to receive(:for).and_return(['Your corncrake called twice this evening.'])
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email).with(hash_including(:content))
        expect(described_class.deliver_digest(user: create(:user), date: facts.date, facts: facts)).to be(true)
      end

      it 'still sends the list email when the model note is unavailable (fallback)' do
        allow(DigestSummary).to receive(:for).and_return(nil)
        fake = double('ses', send_email: true) # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(described_class.deliver_digest(user: create(:user), date: facts.date, facts: facts)).to be(true)
      end
    end
  end
end
