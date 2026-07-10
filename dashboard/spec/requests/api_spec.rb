require 'rails_helper'

RSpec.describe 'API' do
  # The API returns second-language names and illustration URLs, so it exercises the
  # bilingual sample fixture (which ships a few art fixtures), not the English-only example.
  around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

  before do
    travel_to Time.zone.local(2026, 6, 29, 9, 0)
    # Credible: 6 robins (count >= 5) + a confident chough (conf >= 0.6).
    create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin', Confidence: 0.9)
    create(:detection, Sci_Name: 'Pyrrhocorax pyrrhocorax', Com_Name: 'Red-billed Chough', Confidence: 0.95)
    # Not credible: a lone low-confidence hit — must never surface.
    create(:detection, Sci_Name: 'Anas strepera', Com_Name: 'Gadwall', Confidence: 0.27)
  end

  describe 'GET /api/overview' do
    it 'returns the collage nodes, numbers, and bilingual almanac' do
      get '/api/overview'
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['collage']['nodes'].first).to include('sci', 'ga', 'en', 'cx', 'cy', 'flip')
      expect(body['numbers']).to include('species_today', 'detections_today', 'detections_all_time')
      expect(body['almanac']['moon']).to include('name_ga', 'emoji')
      expect(body['window']).to eq(24)
      expect(body['status']).to be_in(%w[listening offline]) # the New & notable status line
    end

    it 'includes the today card: date, capped bullets, sparkline paths, anchors and footer' do
      get '/api/overview'
      today = response.parsed_body['today']
      expect(today).to include('date_label', 'summary', 'source', 'total', 'sparkline', 'anchors', 'footer')
      expect(today['summary']).to include('en', 'ga')  # bilingual bullets
      expect(today['summary']['en'].size).to be <= 4   # the bullet cap
      expect(today['summary']['ga'].size).to be <= 4
      expect(today['sparkline']).to include('path', 'fill', 'w', 'h')
      expect(today['footer'].first).to include('icon', 'en', 'ga')
    end

    it 'excludes the non-credible species from the collage' do
      get '/api/overview'
      names = response.parsed_body['collage']['nodes'].pluck('sci')
      expect(names).to include('Erithacus rubecula').and include('Pyrrhocorax pyrrhocorax')
      expect(names).not_to include('Anas strepera')
    end

    it 'honours the ?h window' do
      get '/api/overview', params: { h: 1 }
      expect(response.parsed_body['window']).to eq(1)
    end

    it 'groups recent newsworthy events into new & notable (a follow is not news)' do
      Event.create!(event_type: 'rarity', sci_name: 'Pyrrhocorax pyrrhocorax', occurred_on: Date.current)
      Event.create!(event_type: 'species', sci_name: 'Passer domesticus', occurred_on: Date.current)
      get '/api/overview'
      notable = response.parsed_body['notable']
      expect(notable.keys).to contain_exactly('rarity', 'first_ever', 'seasonal') # fixed shape
      expect(notable['rarity']).to eq([{ 'sci' => 'Pyrrhocorax pyrrhocorax', 'en' => 'Red-billed Chough',
                                         'ga' => 'Cág cosdearg' }])
      expect(notable['first_ever']).to eq([]) # the 'species' follow is not news
      expect(notable['seasonal']).to eq([])
    end
  end

  describe 'GET /api/stats' do
    it 'returns top species and the by-period buckets' do
      get '/api/stats'
      body = response.parsed_body
      expect(body['top_species'].first).to include('sci', 'count')
      expect(body['by_period'].pluck('label')).to include('All time')
    end

    it 'returns the continuity summary cards' do
      get '/api/stats'
      cards = response.parsed_body['summary_cards']
      expect(cards).to include('species_logged', 'detections_all_time', 'days_listening')
      expect(cards['species_logged']).to eq(2) # robin + chough are credible; gadwall is not
      expect(cards['days_listening']).to be >= 1
    end
  end

  describe 'GET /api/directory' do
    it 'lists the heard life list with conservation status' do
      get '/api/directory'
      body = response.parsed_body
      expect(body['scope']).to eq('heard')
      expect(body['species'].first).to include('sci', 'conservation', 'count', 'today', 'first_seen')
      expect(body['species'].pluck('sci')).not_to include('Anas strepera')
    end

    it 'includes un-heard library species under scope=all' do
      get '/api/directory', params: { scope: 'all' }
      body = response.parsed_body
      expect(body['scope']).to eq('all')
      expect(body['species'].size).to be > Detection.life_list.size
    end
  end

  describe 'GET /api/species/:sci' do
    it 'returns the modal blob for a species' do
      get '/api/species/Erithacus%20rubecula'
      body = response.parsed_body
      expect(body).to include('sci' => 'Erithacus rubecula', 'en' => 'European Robin', 'ga' => 'Spideog')
      expect(body['conservation']).to include('status')
      expect(body['illustrations']).to be_an(Array)
      expect(body['all_time']).to eq(6)
    end

    it 'has no enrichment until a bundle exists' do
      get '/api/species/Erithacus%20rubecula'
      expect(response.parsed_body['enrichment']).to be_nil
    end

    it 'surfaces the latest bundle blocks in order, dropping empty/unsourced ones' do
      EnrichmentBundle.create!(
        sci_name: 'Erithacus rubecula', date: Date.current,
        blocks: [
          { type: 'fact', id: 'f1', text: 'Robins hold winter territories.',
            sources: [{ host: 'rspb.org.uk', url: 'https://rspb.org.uk/robin' }] },
          { type: 'folklore', id: 'l1', gated: true, text: 'A robin at the door foretells a visitor.',
            sources: [{ host: 'duchas.ie', url: 'https://duchas.ie/robin' }] }
        ]
      )
      get '/api/species/Erithacus%20rubecula'
      blocks = response.parsed_body.dig('enrichment', 'blocks')
      expect(blocks.pluck('type', 'text')).to eq([
                                                   ['fact', 'Robins hold winter territories.'],
                                                   ['folklore', 'A robin at the door foretells a visitor.']
                                                 ])
      expect(blocks.first['sources'].first).to include('host' => 'rspb.org.uk', 'url' => 'https://rspb.org.uk/robin')
    end
  end
end
