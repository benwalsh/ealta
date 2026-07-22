require 'rails_helper'

RSpec.describe 'API journal' do
  # Run against the neutral sample profile so the féilire/lore assertions test the mechanism,
  # not any station's real curation (07-07 carries a curated day; Streptopelia carries a tale).
  around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

  before do
    travel_to Time.zone.local(2026, 7, 8, 9, 0) # yesterday is 2026-07-07
    create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                               Confidence: 0.9, Date: '2026-07-07')
    # Stub the narration so the request never calls the model; the controller still does the
    # real emphasis, figures and clamping around it.
    allow(DayNarrator).to receive(:narrate).and_return(
      { bullets: { en: ['The **European Robin** sang through a quiet day.'],
                   ga: ['Chan an **spideog** trí lá ciúin.'] }, source: 'llm', sources: [] }
    )
    # The hero deep-dive pulls the Wikipedia summary via SpeciesInfo — stub that network boundary.
    allow(SpeciesInfo).to receive_messages(english_for: 'A small bird of gardens and hedgerows.', irish_for: nil)
  end

  describe 'GET /api/journal' do
    it 'returns yesterday by default: figures, emphasised narration, notable and bounds' do
      get '/api/journal'
      body = response.parsed_body

      expect(response).to have_http_status(:success)
      expect(body['date']).to eq('2026-07-07')
      expect(body['date_label']).to include('en', 'ga')
      expect(body['figures']).to include('species' => 1, 'detections' => 6)
      expect(body['figures']['busiest']).to include('en' => 'European Robin', 'count' => 6)
      # the primary name is bold and links to its card (data-sci)
      expect(body['summary']['en'].first).to include('data-sci="Erithacus rubecula"').
        and include('>European Robin</strong>')
      expect(body['notable'].keys).to contain_exactly('rarity', 'first_ever', 'seasonal')
      expect(body['available']).to eq('first' => '2026-07-07', 'last' => '2026-07-07')
      # 7 July carries a curated féilire day in the sample profile; the robin has no poem/tale.
      expect(body['day_lore']['title']['en']).to eq("Founders' Day")
      # …and that day carries a curated deep dive (a longer passage + a citation).
      expect(body['day_lore']['lore']['en']).to include('founders')
      expect(body['day_lore']['sources']).to eq([{ 'host' => 'example.org', 'url' => 'https://example.org/founders' }])
      expect(body['lore']).to be_nil
    end

    it "rolls the day's birds last-heard first, locked to the day (Live's Recently heard, past tense)" do
      create(:detection, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                         Confidence: 0.9, Date: '2026-07-07', Time: '21:30:00')
      # …and a bird from the NEXT day, which the day's roll must not reach for.
      create_list(:detection, 6, Sci_Name: 'Turdus merula', Com_Name: 'Eurasian Blackbird',
                                 Confidence: 0.9, Date: '2026-07-08')
      get '/api/journal'
      heard = response.parsed_body['heard']

      # The sparrow at 21:30 sits above the robins at 09:00; the next day's blackbird is absent.
      expect(heard.pluck('sci')).to eq(['Passer domesticus', 'Erithacus rubecula'])
      expect(heard.first).to include('en' => 'House Sparrow', 'count' => 1)
      expect(heard.first['last_time']).to include('21:30')
    end

    it 'quotes the station seed lore, carrying its curated kind and credit' do
      create(:detection, Sci_Name: 'Streptopelia decaocto', Com_Name: 'Eurasian Collared-Dove',
                         Confidence: 0.9, Date: '2026-07-07')
      # The robin was here days ago, so today it is routine — the first-ever dove is the hero.
      create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                                 Confidence: 0.9, Date: '2026-07-05')
      get '/api/journal'
      # A curated entry surfaces its OWN kind (this one is a `tale`) for styling — no longer flattened
      # to 'folklore' — while still pooling with web folklore for selection.
      quote = response.parsed_body['quotes'].first
      expect(quote).to include('kind' => 'tale', 'sci' => 'Streptopelia decaocto')
      expect(quote['text']).to include('deca octo')
      expect(quote['attribution']).to include('Greek folk etymology')
    end

    it 'sets sourced folklore apart as an attributed quote, never woven into prose' do
      create(:detection, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                         Confidence: 0.9, Date: '2026-07-07')
      # Robin routine (heard earlier), so the first-ever sparrow is today's hero and carries the coda.
      create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                                 Confidence: 0.9, Date: '2026-07-05')
      EnrichmentBundle.create!(
        sci_name: 'Passer domesticus', date: '2026-07-07',
        blocks: [{ type: 'folklore', id: 'f1', gated: true,
                   text: 'A sparrow at the window was said to carry news of a traveller.',
                   sources: [{ host: 'duchas.ie', url: 'https://duchas.ie/story/1' }] }]
      )
      get '/api/journal'
      quote = response.parsed_body['quotes'].find { |q| q['kind'] == 'folklore' }
      expect(quote).to include('sci' => 'Passer domesticus', 'attribution' => 'duchas.ie')
      expect(quote['text']).to include('carry news of a traveller')
    end

    it 'trails a narration bullet with the inline citation for the bird it names' do
      # The robin's current bundle carries a Wikipedia-sourced fact; the bullet naming the robin
      # gets that page as a muted inline mark, rather than the citations being lumped at the foot.
      EnrichmentBundle.create!(
        sci_name: 'Erithacus rubecula', date: '2026-07-07',
        blocks: [{ type: 'fact', id: 'f1', text: 'A familiar bird of gardens and hedgerows.',
                   sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/European_robin' }] }]
      )
      get '/api/journal'
      bullet = response.parsed_body['summary']['en'].first
      expect(bullet).to include('<span class="bullet-cites">').
        and include('href="https://en.wikipedia.org/wiki/European_robin"').
        and include('>Wikipedia</a>')
    end

    it 'strips editorial framing from a folklore quote so the lore stands on its own' do
      create(:detection, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                         Confidence: 0.9, Date: '2026-07-07')
      # Robin routine (heard earlier), so the first-ever sparrow is today's hero and carries the coda.
      create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                                 Confidence: 0.9, Date: '2026-07-05')
      EnrichmentBundle.create!(
        sci_name: 'Passer domesticus', date: '2026-07-07',
        blocks: [{ type: 'folklore', id: 'f1', gated: true,
                   text: "In a tale from the Schools' Collection, the sparrow carried news of a traveller.",
                   sources: [{ host: 'duchas.ie', url: 'https://duchas.ie/story/1' }] }]
      )
      get '/api/journal'
      quote = response.parsed_body['quotes'].find { |q| q['kind'] == 'folklore' }
      expect(quote['text']).to eq('The sparrow carried news of a traveller.')
    end

    it 'surfaces a curated legend in full: title, set-apart verse, context note and book credit' do
      allow(StationProfile).to receive(:yaml).and_call_original
      allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(
        'Passer domesticus' => {
          'kind' => 'legend', 'title' => 'The Fate of the Children of Lir',
          'text' => 'She led the children to the edge of the lake…',
          'quote' => "Out to your home, ye swans, on Darvra's wave;",
          'note' => 'Aoife turns the children of Lir into swans.',
          'attribution' => 'trans. P. W. Joyce', 'source_work' => 'Old Celtic Romances',
          'year_translation' => 1879
        }
      )
      create(:detection, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                         Confidence: 0.9, Date: '2026-07-07')
      create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                                 Confidence: 0.9, Date: '2026-07-05') # robin routine → sparrow is hero

      get '/api/journal'
      quote = response.parsed_body['quotes'].first
      expect(quote).to include(
        'kind'   => 'legend',
        'title'  => 'The Fate of the Children of Lir',
        'text'   => 'She led the children to the edge of the lake…',
        'quote'  => "Out to your home, ye swans, on Darvra's wave;",
        'note'   => 'Aoife turns the children of Lir into swans.',
        'credit' => 'trans. P. W. Joyce · Old Celtic Romances (1879)'
      )
    end

    it 'follows the day hero: quotes the first-ever rarity, not the most-detected common bird' do
      # Both carry lore. The sparrow is the most DETECTED (and heard on earlier days, so routine);
      # the golden plover is a first-ever today — far higher importance. The coda must follow the
      # plover, not the sparrow.
      allow(StationProfile).to receive(:yaml).and_call_original
      allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(
        'Passer domesticus'   => { 'kind' => 'poem', 'text' => 'Sparrow verse.', 'attribution' => 's' },
        'Pluvialis apricaria' => { 'kind' => 'poem', 'text' => 'Plover verse.',   'attribution' => 'p' }
      )
      # Sparrow and robin heard for days (routine); plover heard only today (all-time first).
      create_list(:detection, 3, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                                 Confidence: 0.9, Date: '2026-07-05')
      create_list(:detection, 9, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                                 Confidence: 0.9, Date: '2026-07-07')
      create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                                 Confidence: 0.9, Date: '2026-07-05')
      create(:detection, Sci_Name: 'Pluvialis apricaria', Com_Name: 'European Golden Plover',
                         Confidence: 0.9, Date: '2026-07-07')

      get '/api/journal'
      quote = response.parsed_body['quotes'].first
      expect(quote).to include('sci' => 'Pluvialis apricaria', 'kind' => 'poem')
      expect(quote['text']).to eq('Plover verse.')
    end

    it 'draws seed and web folklore from one pool, alternating them for a bird across days' do
      travel_to Time.zone.local(2026, 7, 10, 9, 0) # 07-08 and 07-09 are both completed days
      # One bird whose folklore has two springs — a seed poem and a dúchas passage. Both are just
      # folklore; the single closing quote rotates between them day to day, neither privileged.
      allow(StationProfile).to receive(:yaml).and_call_original
      allow(StationProfile).to receive(:yaml).with('content/bird_lore.yml').and_return(
        'Passer domesticus' => { 'kind' => 'poem', 'text' => 'A seed poem for the sparrow.', 'attribution' => 's' }
      )
      %w[2026-07-05 2026-07-08 2026-07-09].each do |day|
        create_list(:detection, 4, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                                   Confidence: 0.9, Date: day)
      end
      EnrichmentBundle.create!(
        sci_name: 'Passer domesticus', date: '2026-07-09',
        blocks: [{ type: 'folklore', id: 'f1', gated: true,
                   text: 'A sparrow at the window was said to carry news of a traveller.',
                   sources: [{ host: 'duchas.ie', url: 'https://duchas.ie/story/1' }] }]
      )

      seed = 'A seed poem for the sparrow.'
      duchas = 'A sparrow at the window was said to carry news of a traveller.'
      get '/api/journal', params: { date: '2026-07-08' }
      day_one = response.parsed_body['quotes']
      get '/api/journal', params: { date: '2026-07-09' }
      day_two = response.parsed_body['quotes']

      # One quote per journal, drawn from the one pool — but each keeps its OWN kind now: the seed
      # entry its 'poem', the web passage its 'folklore'. The TEXT alternates day to day.
      expect(day_one.pluck('sci')).to eq(['Passer domesticus'])
      expect(day_two.pluck('sci')).to eq(['Passer domesticus'])
      expect([day_one, day_two].map { |q| q.first['kind'] }).to contain_exactly('poem', 'folklore')
      expect([day_one, day_two].map { |q| q.first['text'] }).to contain_exactly(seed, duchas)
    end

    it 'closes on folklore, falling back from a lore-less hero to another of the day\'s birds' do
      create(:detection, Sci_Name: 'Pluvialis apricaria', Com_Name: 'European Golden Plover',
                         Confidence: 0.9, Date: '2026-07-07')
      # Robin routine (heard earlier), so the first-ever plover is the hero — but it has NO folklore
      # (nothing has been written down for it), so the coda falls through to the robin, which does.
      create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                                 Confidence: 0.9, Date: '2026-07-05')
      EnrichmentBundle.create!(
        sci_name: 'Pluvialis apricaria', date: '2026-07-07',
        blocks: [{ type: 'fact', id: 'f1', text: 'Breeds on upland bogs and moors.',
                   sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/x' }] }]
      )
      EnrichmentBundle.create!(
        sci_name: 'Erithacus rubecula', date: '2026-07-07',
        blocks: [{ type: 'folklore', id: 'l1', gated: true, text: 'A robin at the window.',
                   sources: [{ host: 'duchas.ie', url: 'https://duchas.ie/1' }] }]
      )
      get '/api/journal'
      body = response.parsed_body
      # The deep-dive card is gone — the journal no longer repeats the catalogue's basic bird info.
      expect(body).not_to have_key('hero')
      quote = body['quotes'].first
      expect(quote).to include('kind' => 'folklore', 'sci' => 'Erithacus rubecula')
      expect(quote['text']).to eq('A robin at the window.')
    end

    it 'flags a day offline and gaps its sparkline from the frozen coverage' do
      # A day frozen with the mic up for only the first few hours — mostly no data.
      coverage = Array.new(4, true) + Array.new(20, false)
      JournalEntry.create!(date: '2026-07-06', source: 'facts',
                           bullets: { en: ['x'], ga: ['y'] }, coverage: coverage)
      create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                         Confidence: 0.9, Date: '2026-07-06')

      get '/api/journal', params: { date: '2026-07-06' }
      body = response.parsed_body
      expect(body['offline']).to be(true) # only 4 of 24 hours covered
      expect(body['mic_hours']).to eq(4) # …and it says how long the mic actually listened
      expect(body['figures']['duration_seconds']).to eq(4 * 3600) # the stats line's listening time
      expect(body['sparkline']['gaps']).to be_present
      # The gap is shown by the curve breaking, not by a captioned slab, so it carries no label.
      expect(body['sparkline']['gaps'].first.keys).to contain_exactly('x0', 'x1')
    end

    it 'clamps a future/out-of-range date back into the available window' do
      get '/api/journal', params: { date: '2030-01-01' }
      expect(response.parsed_body['date']).to eq('2026-07-07')
    end

    it 'serves a completed earlier day when asked for it' do
      create(:detection, Sci_Name: 'Passer domesticus', Com_Name: 'House Sparrow',
                         Confidence: 0.9, Date: '2026-07-05')
      get '/api/journal', params: { date: '2026-07-05' }
      expect(response.parsed_body['date']).to eq('2026-07-05')
    end
  end
end
