require 'rails_helper'

RSpec.describe Notifier do
  # The hero deep-dive + photo pull from SpeciesInfo — stub those network boundaries.
  before do
    allow(SpeciesInfo).to receive_messages(english_for: 'A secretive rail of hay meadows.', irish_for: nil,
                                           photo_for: nil)
  end

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

    it 'attaches the RFC 8058 one-click unsubscribe headers' do
      ENV['ALERTS_FROM'] = 'alerts@example.com'
      sub = create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      event = create(:event, event_type: 'species', sci_name: 'Crex crex')
      fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
      allow(described_class).to receive(:client).and_return(fake)
      expect(fake).to receive(:send_email) do |args|
        headers = args.dig(:content, :simple, :headers)
        expect(headers).to include(hash_including(name: 'List-Unsubscribe-Post', value: 'List-Unsubscribe=One-Click'))
        expect(headers.find do |h|
          h[:name] == 'List-Unsubscribe'
        end[:value]).to include("/subscriptions/#{sub.token}/unsubscribe")
      end
      described_class.deliver(event: event, subscription: sub)
    ensure
      ENV.delete('ALERTS_FROM')
    end

    it 'skips a suppressed address without calling SES, and still reports success' do
      ENV['ALERTS_FROM'] = 'alerts@example.com'
      sub = create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      event = create(:event, event_type: 'species', sci_name: 'Crex crex')
      EmailSuppression.record_hard_bounce!(sub.email)
      fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
      allow(described_class).to receive(:client).and_return(fake)
      expect(fake).not_to receive(:send_email)
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

      it "embeds the day's notable bird as the letter's picture" do
        hero = { sci: 'Crex crex', slug: 'crex-crex', en: 'Corncrake', ga: 'Traonach' }
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          html = args.dig(:content, :simple, :body, :html, :data)
          expect(html).to include('/birds/crex-crex.png')
          expect(html).to include('Corncrake · Traonach')
          text = args.dig(:content, :simple, :body, :text, :data)
          expect(text).to include("The day's bird: Corncrake · Traonach")
        end
        described_class.deliver_letter(user: create(:user), date: date, entry: entry, hero: hero)
      end

      it 'prefers a credited Commons photo over the illustration for the hero banner' do
        allow(SpeciesInfo).to receive(:photo_for).with('Crex crex').and_return(
          url: 'https://upload.wikimedia.org/corncrake.jpg', credit: 'A. Photographer · CC BY-SA 4.0'
        )
        hero = { sci: 'Crex crex', slug: 'crex-crex', en: 'Corncrake', ga: 'Traonach' }
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          html = args.dig(:content, :simple, :body, :html, :data)
          expect(html).to include('https://upload.wikimedia.org/corncrake.jpg')
          expect(html).to include('A. Photographer · CC BY-SA 4.0')
          expect(html).not_to include('/birds/crex-crex.png') # the photo wins over the illustration
        end
        described_class.deliver_letter(user: create(:user), date: date, entry: entry, hero: hero)
      end

      it 'adds a short deep dive on the hero from its sourced Wikipedia summary' do
        hero = { sci: 'Crex crex', slug: 'crex-crex', en: 'Corncrake', ga: 'Traonach' }
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          html = args.dig(:content, :simple, :body, :html, :data)
          expect(html).to include('About the Corncrake · Traonach')
          expect(html).to include('A secretive rail of hay meadows.')
        end
        described_class.deliver_letter(user: create(:user), date: date, entry: entry, hero: hero)
      end

      it 'gives an empty quiet day a coverage-aware line instead of the bare template' do
        quiet = JournalEntry.new(date: date, source: 'template',
                                 bullets: { en: ['0 species and 0 detections logged today.'], ga: [] },
                                 coverage: Array.new(24, true))
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          text = args.dig(:content, :simple, :body, :text, :data)
          expect(text).to include('A quiet day at the station').and include('listened 24 of 24 hours')
          expect(text).not_to include('0 species')
        end
        described_class.deliver_letter(user: create(:user), date: date, entry: quiet)
      end

      it 'says the station was offline when an empty day had little coverage' do
        offline = JournalEntry.new(date: date, source: 'template', bullets: { en: ['x'], ga: [] },
                                   coverage: Array.new(24, false))
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          expect(args.dig(:content, :simple, :body, :text, :data)).
            to include('The station was offline').and include('recorded 0 of 24 hours')
        end
        described_class.deliver_letter(user: create(:user), date: date, entry: offline)
      end

      it 'carries a one-click unsubscribe link and List-Unsubscribe header keyed to the user' do
        user = create(:user)
        path = "/letter/#{user.letter_token}/unsubscribe"
        fake = double('ses') # rubocop:disable RSpec/VerifiedDoubles
        allow(described_class).to receive(:client).and_return(fake)
        expect(fake).to receive(:send_email) do |args|
          simple = args[:content][:simple]
          expect(simple.dig(:body, :html, :data)).to include(path).and include('unsubscribe in one click')
          expect(simple.dig(:body, :text, :data)).to include('Unsubscribe: ').and include(path)
          expect(simple[:headers].find { |h| h[:name] == 'List-Unsubscribe' }[:value]).to include(path)
        end
        described_class.deliver_letter(user: user, date: date, entry: entry)
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
