require 'rails_helper'

RSpec.describe 'API overview' do
  before do
    create_list(:detection, 6, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin', Confidence: 0.9)
  end

  # The note is re-stitched every 30 minutes, and that regeneration used to happen INSIDE this
  # request: DailyFacts plus a DayNarrator call (Bedrock, on the cloud). One visitor in every
  # thirty minutes paid seconds for it while the SPA held every collage image behind the
  # response — measured at 1,014ms in a Lighthouse run against the live site, against ~140ms
  # for the loads either side of it. The work is identical whoever triggers it, so it belongs
  # in a job; the request may only notice the staleness.
  describe 'the daily summary is warmed off the request path' do
    it 'never narrates inside the request, even when the note is stale' do
      allow(TodaySummary).to receive(:stale?).and_return(true)
      expect(DayNarrator).not_to receive(:narrate)

      get '/api/overview'

      expect(response).to have_http_status(:success)
    end

    it 'enqueues the warm job when the note is stale' do
      allow(TodaySummary).to receive(:stale?).and_return(true)

      expect { get '/api/overview' }.to have_enqueued_job(WarmTodaySummaryJob)
    end

    it 'enqueues nothing when the note is already fresh' do
      allow(TodaySummary).to receive(:stale?).and_return(false)

      expect { get '/api/overview' }.not_to have_enqueued_job(WarmTodaySummaryJob)
    end

    # A stale window ends with a burst of readers arriving together. Each one enqueueing its
    # own narration would mean several identical Bedrock calls for one note.
    #
    # Needs a REAL cache store: the test environment runs :null_store, where the `unless_exist`
    # claim can never be held and every reader would win it. That is also why the job re-checks
    # staleness itself — on ECS the default FileStore is per-container, so the claim narrows
    # this race rather than closing it, and the job is what actually guarantees one narration.
    it 'enqueues once for a burst of readers inside the same stale window' do
      allow(TodaySummary).to receive(:stale?).and_return(true)
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      expect do
        3.times { get '/api/overview' }
      end.to have_enqueued_job(WarmTodaySummaryJob).exactly(:once)
    end

    # Enqueueing must never be able to break a page: without a queue the reader still gets the
    # note that was already cached.
    it 'still serves the page when enqueueing fails' do
      allow(TodaySummary).to receive(:stale?).and_return(true)
      allow(WarmTodaySummaryJob).to receive(:perform_later).and_raise(StandardError, 'no queue')

      get '/api/overview'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('today')
    end
  end

  # The endpoint is served from the CDN edge (a narrow exception to the CachingDisabled default
  # — see the /api/overview behaviour in cdn.tf). That is only safe while the payload is the
  # same for everybody, so the properties it rests on are asserted here rather than trusted:
  # if someone makes this per-reader, these fail before it can leak one reader's page to
  # another.
  describe 'the window stats line (detections · species · duration)' do
    it 'carries the window figures, with a listening duration' do
      get '/api/overview'
      stats = response.parsed_body['stats']

      expect(stats).to include('detections' => 6, 'species' => 1)
      # No heartbeats in the test data → the 24h window reads as wholly covered (24h listening).
      expect(stats['duration_seconds']).to eq(24 * 3600)
    end

    it 'drops the duration for the all-time span (a lifetime is not a listening duration)' do
      get '/api/overview', params: { h: 1_000_000 }
      expect(response.parsed_body['stats']['duration_seconds']).to be_nil
    end
  end

  describe 'is safe to serve from a shared cache' do
    it 'is publicly cacheable' do
      get '/api/overview'

      expect(response.headers['Cache-Control']).to include('public').and include('max-age=30')
    end

    it 'sets no cookie that a shared cache could hand to the next reader' do
      get '/api/overview'

      expect(response.headers['Set-Cookie']).to be_nil
    end

    it 'returns the same body with and without a session cookie' do
      get '/api/overview'
      anonymous = response.body

      get '/api/overview', headers: { 'Cookie' => '_ealta_session=someone-elses-session' }

      expect(response.body).to eq(anonymous)
    end
  end

  describe WarmTodaySummaryJob do
    it 'refreshes the note when it is stale' do
      allow(TodaySummary).to receive(:stale?).and_return(true)
      expect(TodaySummary).to receive(:refresh_if_stale).with(enrich: false)

      described_class.new.perform
    end

    # Two readers can slip past the controller's claim; the job re-checks rather than trusting
    # the enqueue-time snapshot, so the second one does not pay for a second narration.
    it 'does nothing when another run already refreshed it' do
      allow(TodaySummary).to receive(:stale?).and_return(false)
      expect(TodaySummary).not_to receive(:refresh_if_stale)

      described_class.new.perform
    end
  end
end
