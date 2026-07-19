require 'rails_helper'

RSpec.describe 'Panel' do
  # The almanac reads its cache from storage/almanac.json — a gitignored artefact that only a
  # station which has actually run writes. Left alone, the panel's tide zone rendered only on a
  # machine that happened to have one lying about with extrema later than the frozen clock, so
  # these specs passed locally and failed on a fresh clone or in CI. Pin a fixture instead: the
  # real read/live_tide logic against fixed input.
  let(:almanac_dir) { Pathname(Dir.mktmpdir) }
  let(:almanac_file) do
    almanac_dir.join('almanac.json').tap do |f|
      f.write({
        coords:       { lat: 53.35, lon: -9.88, place: { en: nil, ga: nil } },
        weather:      { temp: 16, text: 'fair', text_ga: 'breá', emoji: '🌤️' },
        sun:          { rise: '05:35', set: '21:56' },
        # Straddles the 29 June 09:00 these specs freeze at, so the NEXT turning point is
        # always the 10:20Z high — the tide zone can't depend on the day it's run.
        tide_extrema: [{ t: '2026-06-29T04:15:00Z', type: 'low' },
                       { t: '2026-06-29T10:20:00Z', type: 'high' },
                       { t: '2026-06-29T16:40:00Z', type: 'low' }],
        tide_station: { en: 'The harbour', ga: 'An caladh' },
        fetched_at:   '2026-06-29T08:00:00+01:00'
      }.to_json)
    end
  end

  after { FileUtils.remove_entry(almanac_dir) if almanac_dir.exist? }

  # The panel surfaces exist only for a station WITH a configured screen (station.yml
  # `screen:`), so these specs run as one. The gating itself is asserted at the bottom.
  before do
    stub_const('Almanac::STORE', almanac_file)
    allow(Station).to receive(:screen).
      and_return({ name: 'Test panel', width: 480, height: 800 })
  end

  # The bare collage SVG the e-ink shooter screenshots — no web chrome.
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
    expect(response.body).to include('Test panel') # the configured screen's name labels the emulator
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

    # Four zones and nothing else: the plate, one piece of news, the almanac bar with the
    # tide, and the footer. Anything else is spending pixels the 480x800 panel hasn't got.
    it 'is four zones — plate, news, almanac bar with the tide, and the footer line' do
      get '/station'
      ['class="plate"', 'class="news"', 'class="bar"', 'class="tide"', 'class="foot-line"'].each do |zone|
        expect(response.body).to include(zone), "expected the panel to carry #{zone}"
      end
    end

    # The masthead was the most expensive thing on the screen, and the panel hangs on a wall
    # in the house it belongs to — it does not need to introduce itself.
    it 'carries no wordmark' do
      get '/station'
      expect(response.body).not_to include('class="wordmark"')
    end

    # The plate is a frozen daily edition, so the news line is the only thing that moves:
    # the day's most recent FIRST arrival, with its time.
    it "leads with the day's most recent arrival and its time" do
      Station.language = :en
      get '/station'
      expect(response.body).to include('class="news-name">European Robin')
      expect(response.body).to match(/class="news-when">\s*\d{2}:\d{2}/)
    end

    # Before the first bird — every night after midnight, often for hours — "0 species today"
    # is true but a bleak thing to hang on a wall, so the panel says what it is doing.
    it 'rests in the listening state before anything is heard' do
      Detection.delete_all
      get '/station'
      expect(response.body).to include('ag éisteacht') # Irish by default
    end

    # An honest stamp of when this impression was taken — date AND time, since a time alone
    # can't tell you whether the panel froze an hour ago or a week ago. Not a live clock.
    it 'stamps the impression with a date and a time, not a clock' do
      Station.language = :en
      get '/station'
      expect(response.body).to include('class="stamp"')
      expect(response.body).to match(/29 June · \d{2}:\d{2}/)
      expect(response.body).not_to include('class="clock"')
    end

    # Coarsened to the half hour ON PURPOSE: the shooter skips the push when the render is
    # byte-identical, and the Impression has no partial refresh — a minute-precise clock would
    # force a full ~30-40s flash on every cycle to say nothing new.
    it 'coarsens the stamp to the half hour so an unchanged panel is not reprinted' do
      travel_to Time.zone.local(2026, 6, 29, 9, 47) do
        get '/station'
        expect(response.body).to include('29 June · 09:30')
      end
    end

    # The panel speaks ONE language throughout — the admin-set one, never mixed.
    it 'renders every string in the configured language' do
      Station.language = :en
      get '/station'
      expect(response.body).to match(/(High|Low) tide/)          # the tide names its point in English
      expect(response.body).not_to include('speiceas inniu')
      expect(response.body).not_to include('Lán mara')           # …and never in Irish alongside it
      expect(response.body).not_to include('Lag trá')
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

  describe 'a station with no screen configured' do
    it '404s every panel surface — there is no glass to render for' do
      allow(Station).to receive(:screen).and_return(nil)
      %w[/panel /emulator /station /station/preview].each do |path|
        get path
        expect(response).to have_http_status(:not_found), "expected 404 for #{path}"
      end
    end
  end
end
