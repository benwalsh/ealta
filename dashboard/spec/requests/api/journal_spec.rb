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
      expect(body['lore']).to be_nil
    end

    it 'closes with a curated bird poem/tale when one of the day\'s birds has one' do
      create(:detection, Sci_Name: 'Streptopelia decaocto', Com_Name: 'Eurasian Collared-Dove',
                         Confidence: 0.9, Date: '2026-07-07')
      get '/api/journal'
      lore = response.parsed_body['lore']
      expect(lore).to include('kind' => 'tale', 'sci' => 'Streptopelia decaocto')
      expect(lore['text']).to include('deca octo')
      expect(lore['attribution']).to include('Greek folk etymology')
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
