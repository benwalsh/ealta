require 'rails_helper'

RSpec.describe 'Panel' do
  # The bare 800x480 SVG the Inky shooter screenshots — no web chrome.
  it 'renders the SVG without the nav or window picker' do
    create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    get '/panel'
    expect(response).to have_http_status(:success)
    expect(response.body).to include('<svg')
    expect(response.body).not_to include('window-pick')
    expect(response.body).not_to include('class=\'slider\'')
  end

  # The standalone Inky mock-up: a framed canvas + the Spectra-6 dither, client-side.
  it 'serves the emulator page with the panel canvas and Spectra-6 palette' do
    get '/emulator'
    expect(response).to have_http_status(:success)
    expect(response.body).to include('id="panel"').and include('SPECTRA6')
    expect(response.body).to include('Inky Impression 7.3')
  end

  # /station is the CLEAN 480x800 device screen the Inky shows and the shooter captures:
  # one calm collage in the house style, no frame and no e-ink filter (the panel dithers
  # a full-colour source itself), no rotation, no stats grid (that's /kiosk).
  describe 'GET /station' do
    before do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    end

    it 'renders the bare collage screen — no frame, no e-ink filter, no rotation' do
      get '/station'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<svg').and include('class="screen')
      expect(response.body).not_to include('id="eink"') # the filter is preview-only
      expect(response.body).not_to include('Spectra 6') # the frame/spec is preview-only
      expect(response.body).not_to include('stat-grid')
    end

    # The plate is a frozen daily edition; the day's growth shows only in the live line —
    # the running species count and the most recent arrival with its time.
    it 'shows the running species count and the most recent arrival' do
      Station.language = :en
      get '/station'
      expect(response.body).to include('1 species today')
      expect(response.body).to match(/\+ European Robin at \d{2}:\d{2}/)
    end

    # An honest "updated" stamp + a listening status marker — NOT a live clock.
    it 'stamps when it was updated and shows the recorder status, not a clock' do
      Station.language = :en
      get '/station'
      expect(response.body).to include('class="status"')
      expect(response.body).to match(/updated \d{2}:\d{2}/)
      expect(response.body).to include('listening')          # a recent detection → alive
      expect(response.body).not_to include('class="clock"')  # the live clock is gone
    end

    # With nothing heard today, the arrival line rests in the listening state.
    it 'rests in the listening state before anything is heard' do
      Detection.delete_all
      get '/station'
      expect(response.body).to include('ag éisteacht') # Irish by default
    end

    # The panel speaks ONE language throughout — the admin-set one, never mixed.
    it 'renders every string in the configured language' do
      Station.language = :en
      get '/station'
      expect(response.body).to include('species today').and include('updated').and include('see more at')
      expect(response.body).not_to include('speiceas inniu')
    end
  end

  # /station/preview is the desktop emulation: the same screen, wrapped in the timber
  # frame and run through the CSS/SVG Spectra-6 approximation.
  describe 'GET /station/preview' do
    before do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    end

    it 'renders the framed, e-ink-filtered emulation of the same screen' do
      get '/station/preview'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('class="screen').and include('id="eink"')
      expect(response.body).to include('Spectra 6').and include('inky')
    end
  end

  # /kiosk is the passive-display surface: the four cards in the DOM at once,
  # cycled client-side by the kiosk Stimulus controller. No chrome.
  describe 'GET /kiosk' do
    before do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    end

    it 'renders the four cards for the cycling display' do
      get '/kiosk'
      expect(response).to have_http_status(:success)
      expect(response.body.scan('data-kiosk-target').size).to eq(4)
      expect(response.body).to include('kiosk')       # the controller drives the cycle
      expect(response.body).to include('stat-grid')   # the numbers card lives here now
    end
  end
end
