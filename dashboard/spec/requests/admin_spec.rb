require 'rails_helper'

RSpec.describe 'Admin' do
  # The sample profile is bilingual (ga, en) with an Irish default — so the language picker
  # and the language-change assertions have two languages to work with.
  around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

  let(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'admin-1',
      info: { email: 'boss@example.com', name: 'Boss', image: nil }
    )
  end

  def sign_in
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    Rails.application.env_config['omniauth.auth'] = auth
    get '/auth/google_oauth2/callback'
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete('omniauth.auth')
  end

  it 'bounces anonymous visitors home' do
    get '/admin'
    expect(response).to redirect_to('/')
  end

  it 'bounces signed-in non-admins home (fail-closed)' do
    sign_in # not in ADMIN_EMAILS
    get '/admin'
    expect(response).to redirect_to('/')
  end

  it 'boots the SPA with the admin panel open (HTML) for admins' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    get '/admin'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="ealta-app"')
    expect(response.body).to include('&quot;open_panel&quot;:&quot;admin&quot;')
  end

  it 'serves the health snapshot as JSON for admins' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    get '/admin', headers: { 'Accept' => 'application/json' }
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('listening', 'alerts', 'backup', 'station')
    expect(body['station']['options'].pluck('name')).to include('English', 'Gaeilge')
    # Whether the restart control is offered at all depends on this.
    expect(body['listening']).to include('restartable')
  end

  it 'serialises only what the console acts on — no adapter/region/tally trivia' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    get '/admin', headers: { 'Accept' => 'application/json' }
    body = response.parsed_body
    expect(body).not_to have_key('system')
    expect(body['listening']).not_to include('detections_all_time', 'species_all_time')
    expect(body['alerts']).not_to include('following', 'standing_rules', 'last_event')
  end

  it 'returns 403 (not an HTML redirect) to a non-admin JSON caller' do
    sign_in # not in ADMIN_EMAILS
    get '/admin', headers: { 'Accept' => 'application/json' }
    expect(response).to have_http_status(:forbidden)
  end

  it 'lets an admin change the station language' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    expect { patch '/admin/station', params: { station: { language: 'en' } } }.
      to change(Station, :language).from(:ga).to(:en)
    expect(response).to redirect_to('/admin')
  end

  it 'ignores a bad language and keeps the current one' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    expect { patch '/admin/station', params: { station: { language: 'fr' } } }.
      not_to change(Station, :language)
  end

  it 'refuses the settings change for non-admins (fail-closed)' do
    sign_in # not an admin
    expect { patch '/admin/station', params: { station: { language: 'en' } } }.
      not_to change(Station, :language)
    expect(response).to redirect_to('/')
  end

  describe 'journal & letter dev tools' do
    before { allow_any_instance_of(User).to receive(:admin?).and_return(true) }

    it "regenerates a day's journal, replacing the frozen row" do
      sign_in
      travel_to Time.zone.local(2026, 7, 8, 9, 0) do
        create(:detection, Sci_Name: 'Turdus merula', Com_Name: 'Blackbird', Confidence: 0.9, Date: '2026-07-07')
        allow(DayNarrator).to receive(:narrate).and_return(
          { bullets: { en: ['A fresh note.'], ga: ['Nóta úr.'] }, source: 'llm', sources: [] }
        )
        old = JournalEntry.create!(date: '2026-07-07', source: 'facts', bullets: { en: ['Stale.'], ga: ['Sean.'] })

        post '/admin/journal/regenerate', params: { date: '2026-07-07' }

        expect(response).to redirect_to('/admin')
        entry = JournalEntry.find_by(date: '2026-07-07')
        expect(entry.id).not_to eq(old.id) # the old row was dropped and rebuilt
        expect(entry.bullets['en']).to eq(['A fresh note.'])
      end
    end

    it 'rejects a bad date with an alert rather than crashing' do
      sign_in
      post '/admin/journal/regenerate', params: { date: 'not-a-date' }
      expect(response).to redirect_to('/admin')
      expect(flash[:alert]).to be_present
    end

    # Mailing every subscriber is the scheduler's job (DailyEmailSweep). No request should be
    # able to do it, so the route is gone rather than merely unlinked.
    it 'exposes no send-to-every-subscriber route' do
      expect { Rails.application.routes.recognize_path('/admin/letter/send', method: :post) }.
        to raise_error(ActionController::RoutingError)
    end

    it "previews a day's letter without sending anything" do
      sign_in
      JournalEntry.create!(date: '2026-07-07', source: 'facts', bullets: { en: ['A fresh note.'], ga: ['Nóta.'] })
      expect(Notifier).not_to receive(:deliver_letter)

      get '/admin/letter/preview', params: { date: '2026-07-07' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('A fresh note.')
    end

    # JournalEntry.for is find-or-CREATE, so reaching for it here would have made a read-only
    # preview write (and narrate) a journal row for any date typed into the box.
    it 'previews without creating a journal for a day that has none' do
      sign_in
      expect { get '/admin/letter/preview', params: { date: '1999-01-01' } }.
        not_to change(JournalEntry, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'sends a test letter to the admin alone, leaving the once-a-day guard untouched' do
      sign_in
      me = User.find_by(email: 'boss@example.com')
      JournalEntry.create!(date: '2026-07-07', source: 'facts', bullets: { en: ['A fresh note.'], ga: ['Nóta.'] })
      allow(Notifier).to receive(:enabled?).and_return(true)
      expect(Notifier).to receive(:deliver_letter).
        with(hash_including(user: me, date: Date.new(2026, 7, 7))).and_return(true)

      post '/admin/letter/test', params: { date: '2026-07-07' }

      # A test send must never mark the admin as already-sent for the real sweep.
      expect(me.reload.last_digest_on).to be_nil
    end

    # The broadcast is the most dangerous thing in the console: irreversible, external, and
    # aimed at real people. The gate has to hold server-side, not just in the UI.
    describe 'a broadcast to the letter’s readers' do
      let!(:reader) do
        create(:user).tap { |u| u.subscriptions.create!(alert_type: 'roundup', cadence: 'digest') }
      end
      # The console talks JSON; respond_admin's HTML branch is the old redirect path.
      let(:as_json) { { 'Accept' => 'application/json' } }

      before do
        sign_in
        allow(Notifier).to receive(:enabled?).and_return(true)
      end

      it 'previews the words without sending anything' do
        expect(Notifier).not_to receive(:deliver_blast)

        post '/admin/blast/preview', params: { subject: 'Away a fortnight', body: 'The mic is off.' }

        expect(response.parsed_body['html']).to include('Away a fortnight').and include('The mic is off.')
      end

      it 'refuses to send unless the reader count is typed out exactly' do
        expect(Blast).not_to receive(:deliver_all)

        post '/admin/blast', params: { subject: 'Away', body: 'Off.', confirm: 'SEND' }, headers: as_json

        expect(response.parsed_body['message']).to include('Type 1 to confirm')
      end

      it 'sends only to the letter’s readers once confirmed' do
        expect(Blast).to receive(:deliver_all).
          with(subject: 'Away', body: 'Off.').and_return(1)

        post '/admin/blast',
             params: { subject: 'Away', body: 'Off.', confirm: Blast.count.to_s }, headers: as_json

        expect(response.parsed_body).to include('ok' => true)
      end

      it 'does not send an empty message' do
        expect(Blast).not_to receive(:deliver_all)
        post '/admin/blast',
             params: { subject: 'Away', body: '   ', confirm: Blast.count.to_s }, headers: as_json
        expect(response.parsed_body['ok']).to be(false)
      end

      it 'is fail-closed — a non-admin cannot broadcast' do
        allow_any_instance_of(User).to receive(:admin?).and_return(false)
        expect(Blast).not_to receive(:deliver_all)
        post '/admin/blast', params: { subject: 'Away', body: 'Off.', confirm: '1' }
        expect(response).to redirect_to('/')
      end

      # Nobody who never asked for email should ever receive a broadcast.
      it 'counts only readers on the letter, not every account' do
        create(:user) # an account with no letter subscription
        expect(Blast.count).to eq(1)
        expect(Blast.recipients).to contain_exactly(reader)
      end
    end

    describe "the keeper's note for a day" do
      let(:day) { Date.new(2026, 7, 7) }

      before do
        sign_in
        JournalEntry.create!(date: day, source: 'facts', bullets: { en: ['A fresh note.'], ga: ['Nóta.'] })
      end

      # A note is something you say AHEAD, so with no date it attaches to the day the next
      # letter covers — the one still in progress — decided by the station's timezone, not the
      # browser's. The console doesn't ask you to pick a day at all.
      it 'defaults to the day the next letter covers' do
        travel_to Time.zone.local(2026, 7, 9, 14, 0) do
          put '/admin/note', params: { note: 'The feeders are down tomorrow.' }
          expect(DayNote.body_for(Date.new(2026, 7, 9))).to eq('The feeders are down tomorrow.')

          get '/admin/note', headers: { 'Accept' => 'application/json' }
          expect(response.parsed_body).to include('date' => '2026-07-09',
                                                  'note' => 'The feeders are down tomorrow.')
        end
      end

      it 'saves a note, reads it back, and clears it when emptied' do
        put '/admin/note', params: { date: day.iso8601, note: '  The feeders were down.  ' }
        expect(DayNote.body_for(day)).to eq('The feeders were down.') # trimmed

        get '/admin/note', params: { date: day.iso8601 }, headers: { 'Accept' => 'application/json' }
        expect(response.parsed_body).to include('note' => 'The feeders were down.', 'sent' => false)

        put '/admin/note', params: { date: day.iso8601, note: '   ' }
        expect(DayNote.body_for(day)).to be_nil # blank means absent, not an empty note
      end

      it "carries the note in that day's letter" do
        DayNote.write(date: day, body: 'The feeders were down.')
        get '/admin/letter/preview', params: { date: day.iso8601 }
        expect(response.body).to include('A note from the station').and include('The feeders were down.')
      end

      # The whole reason a note lives in its own table: regenerate_journal destroys and recreates
      # the entry, so a note stored ON the entry would be lost every rebuild.
      it 'survives rebuilding that day’s journal' do
        DayNote.write(date: day, body: 'The feeders were down.')
        allow(DayNarrator).to receive(:narrate).
          and_return({ bullets: { en: ['Rebuilt.'], ga: ['Athtógtha.'] }, source: 'llm', sources: [] })

        post '/admin/journal/regenerate', params: { date: day.iso8601 }

        expect(DayNote.body_for(day)).to eq('The feeders were down.')
      end
    end

    it 'is fail-closed — a non-admin cannot send a test letter' do
      sign_in # not an admin
      allow_any_instance_of(User).to receive(:admin?).and_return(false)
      expect(Notifier).not_to receive(:deliver_letter)
      post '/admin/letter/test', params: { date: '2026-07-07' }
      expect(response).to redirect_to('/')
    end
  end

  describe 'POST /admin/species/refresh' do
    # There is no shell into the cloud task (ECS Express Mode has no ECS Exec), so this is the
    # only way to re-derive descriptions where it matters — against the cloud database, with
    # the cloud's model.
    it 'is admin-gated like every other mutating action' do
      sign_in # not in ADMIN_EMAILS
      post '/admin/species/refresh'
      expect(response).to redirect_to('/')
    end

    it 'queues the sweep rather than doing two model calls per bird in the request' do
      allow_any_instance_of(User).to receive(:admin?).and_return(true)
      sign_in
      expect { post '/admin/species/refresh', params: { refresh: true }, as: :json }.
        to have_enqueued_job(SpeciesContentSweepJob).with(force: true)
      expect(response.parsed_body['ok']).to be(true)
    end

    it 'fills only the gaps when not asked to re-derive' do
      allow_any_instance_of(User).to receive(:admin?).and_return(true)
      sign_in
      expect { post '/admin/species/refresh', as: :json }.
        to have_enqueued_job(SpeciesContentSweepJob).with(force: false)
    end
  end
end
