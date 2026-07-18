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
