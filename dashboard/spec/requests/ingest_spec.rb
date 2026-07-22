require 'rails_helper'

RSpec.describe 'Ingest' do
  let(:token) { 'sekret-ingest-token' }
  let(:rows) do
    [
      { Date: '2026-07-02', Time: '22:00:00', Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
        Confidence: 0.91, Lat: 1.0, Lon: 2.0, Week: 27, File_Name: 'a.wav', dedupe_key: 'key-a' },
      { Date: '2026-07-02', Time: '22:01:00', Sci_Name: 'Pica pica', Com_Name: 'Eurasian Magpie',
        Confidence: 0.88, Lat: 1.0, Lon: 2.0, Week: 27, File_Name: 'a.wav', dedupe_key: 'key-b' }
    ]
  end

  def ingest(body, bearer: token)
    headers = bearer ? { 'Authorization' => "Bearer #{bearer}" } : {}
    post '/ingest/detections', params: { detections: body }, headers: headers, as: :json
  end

  context 'when CLOUD_INGEST_TOKEN is unset (the Pi)' do
    it 'is disabled (404) so it never accepts writes' do
      ingest(rows)
      expect(response).to have_http_status(:not_found)
    end

    it 'disables the heartbeats endpoint too' do
      post '/ingest/heartbeats', params: { heartbeats: [] }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'disables the vitals endpoint too' do
      post '/ingest/vitals', params: { vitals: {} }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when a token is configured (the cloud)' do
    around do |example|
      ENV['CLOUD_INGEST_TOKEN'] = token
      example.run
    ensure
      ENV.delete('CLOUD_INGEST_TOKEN')
    end

    # Ingest fires the LLM "today" refresh; stub it so tests never dial Bedrock.
    before { allow(TodaySummary).to receive(:refresh_if_stale) }

    it 'refreshes the today summary once a batch lands' do
      expect(TodaySummary).to receive(:refresh_if_stale)
      ingest(rows)
    end

    it 'rejects a missing or wrong bearer token' do
      ingest(rows, bearer: nil)
      expect(response).to have_http_status(:unauthorized)
      ingest(rows, bearer: 'wrong')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'upserts the batch' do
      expect { ingest(rows) }.to change(Detection, :count).by(2)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['upserted']).to eq(2)
      expect(Detection.find_by(dedupe_key: 'key-a').Sci_Name).to eq('Erithacus rubecula')
    end

    it 'is idempotent — re-POSTing the same batch adds nothing' do
      ingest(rows)
      expect { ingest(rows) }.not_to change(Detection, :count)
    end

    it 'skips rows without a dedupe_key' do
      expect { ingest([rows.first.except(:dedupe_key)]) }.not_to change(Detection, :count)
    end

    describe 'heartbeats — the liveness half of the push' do
      let(:ticks) do
        [{ at: 2.minutes.ago.strftime('%F %T'), source: 'live-mic', dedupe_key: 'hb-a' },
         { at: 1.minute.ago.strftime('%F %T'), source: 'live-mic', dedupe_key: 'hb-b' }]
      end

      def ingest_ticks(body, bearer: token)
        headers = bearer ? { 'Authorization' => "Bearer #{bearer}" } : {}
        post '/ingest/heartbeats', params: { heartbeats: body }, headers: headers, as: :json
      end

      it 'upserts ticks, keyed on dedupe_key' do
        ingest_ticks(ticks)
        expect(response.parsed_body['upserted']).to eq(2)
        expect(Heartbeat.pluck(:dedupe_key)).to contain_exactly('hb-a', 'hb-b')
      end

      it 'is idempotent — re-POSTing the same ticks adds nothing' do
        ingest_ticks(ticks)
        expect { ingest_ticks(ticks) }.not_to change(Heartbeat, :count)
      end

      it 'rejects a bad token and skips keyless rows' do
        ingest_ticks(ticks, bearer: 'wrong')
        expect(response).to have_http_status(:unauthorized)
        expect { ingest_ticks([ticks.first.except(:dedupe_key)]) }.not_to change(Heartbeat, :count)
      end

      it 'prunes ticks older than the retention window' do
        stale = create(:heartbeat, at: 3.days.ago, dedupe_key: 'old')
        ingest_ticks(ticks)
        expect(Heartbeat.exists?(stale.id)).to be(false)
      end
    end

    # The third thing the push carries, and the only one that isn't a stream: current state,
    # one row, overwritten. See DeviceVital and birdnet/vitals.py.
    describe 'vitals — the state of the box' do
      let(:report) do
        { at: '2026-07-20T09:00:00Z', git_sha: 'deadbee', git_dirty: true, boot_at: '2026-07-18T06:00:00Z',
          panel_ran_at: '2026-07-20T08:55:00Z', panel_pushed_at: '2026-07-20T07:00:00Z', panel_outcome: 'skipped',
          services: { listener: { state: 'active', restarts: 2 } },
          litestream_at: '2026-07-20T08:40:00Z', disk_free_mb: 12_000, disk_total_mb: 30_000,
          cpu_temp_c: 51.3, undervoltage_now: false, undervoltage_since_boot: true, mic_name: 'USBMIC1' }
      end

      def ingest_vitals(body, bearer: token)
        headers = bearer ? { 'Authorization' => "Bearer #{bearer}" } : {}
        post '/ingest/vitals', params: { vitals: body }, headers: headers, as: :json
      end

      it 'stores the report as a single row' do
        expect { ingest_vitals(report) }.to change(DeviceVital, :count).by(1)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['stored']).to be(true)
        row = DeviceVital.current
        expect(row.git_sha).to eq('deadbee')
        expect(row.git_dirty).to be(true)
        expect(row.undervoltage_since_boot).to be(true)
        expect(row.services).to eq('listener' => { 'state' => 'active', 'restarts' => 2 })
      end

      # The shape that makes this NOT a stream: pushing again overwrites rather than appends,
      # so there is never more than one row however long the station runs.
      it 'overwrites the same row on every push' do
        ingest_vitals(report)
        expect { ingest_vitals(report.merge(cpu_temp_c: 61.0)) }.not_to change(DeviceVital, :count)
        expect(DeviceVital.current.cpu_temp_c).to eq(61.0)
      end

      # The device's clock and ours are kept apart on purpose: staleness is measured against
      # received_at, so a Pi whose NTP has drifted can't report itself as current.
      it 'keeps the device clock and the server clock apart' do
        ingest_vitals(report)
        row = DeviceVital.current
        expect(row.reported_at).to eq(Time.utc(2026, 7, 20, 9, 0, 0))
        expect(row.received_at).to be_within(5.seconds).of(Time.current)
      end

      # Collection is best-effort, so a mostly-blank report is a legitimate one (a dev box has
      # no vcgencmd and no systemctl). Unknown must land as null, never as zero or false.
      it 'accepts a report whose collectors mostly failed, storing unknowns as null' do
        ingest_vitals({ at: '2026-07-20T09:00:00Z', git_sha: 'deadbee' })
        row = DeviceVital.current
        expect(row.cpu_temp_c).to be_nil
        expect(row.undervoltage_now).to be_nil
        expect(row.services).to be_nil
      end

      it 'stores nothing at all for an empty report' do
        expect { ingest_vitals({}) }.not_to change(DeviceVital, :count)
        expect(response.parsed_body['stored']).to be(false)
      end

      # The columns are the contract. A device running a newer or tampered-with vitals.py must
      # not be able to widen it, and services must not become a hole for arbitrary JSON.
      it 'drops unknown fields and rebuilds each service entry' do
        ingest_vitals(report.merge(secret_token: 'nope', lat: 53.4,
                                   services: { listener: { state: 'active', restarts: 2, extra: 'x' } }))
        expect(DeviceVital.current.services).to eq('listener' => { 'state' => 'active', 'restarts' => 2 })
        expect(DeviceVital.current.attributes).not_to include('lat', 'secret_token')
      end

      it 'rejects a missing or wrong bearer token' do
        ingest_vitals(report, bearer: nil)
        expect(response).to have_http_status(:unauthorized)
        ingest_vitals(report, bearer: 'wrong')
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Generate-on-detect: the station knows a species has arrived long before anyone clicks it,
  # so the modal's content is prepared then rather than during someone's first click (which
  # measured ~11s of Wikipedia + two sequential model calls).
  describe 'preparing species content' do
    around do |example|
      ENV['CLOUD_INGEST_TOKEN'] = token
      example.run
      ENV.delete('CLOUD_INGEST_TOKEN')
    end

    it 'enqueues a job for each species that has no content yet' do
      expect { ingest(rows) }.to have_enqueued_job(PrepareSpeciesContentJob).twice
      expect(response).to have_http_status(:ok)
    end

    it 'skips a species whose content is already stored' do
      # Only the magpie should be queued; the robin is already prepared.
      SpeciesInfo.create!(sci_name: 'Erithacus rubecula', description: 'A robin.',
                          fetched_at: Time.current, fetched_ga_at: Time.current,
                          fetched_song_at: Time.current)
      expect { ingest(rows) }.
        to have_enqueued_job(PrepareSpeciesContentJob).with('Pica pica').exactly(:once)
    end

    it 'still stores the batch when queueing blows up' do
      # The mirror copy is the point of the request; preparation is a nicety on top of it.
      allow(SpeciesInfo).to receive(:missing_content).and_raise(StandardError, 'queue down')
      ingest(rows)
      expect(response).to have_http_status(:ok)
      expect(Detection.count).to eq(2)
    end
  end
end
