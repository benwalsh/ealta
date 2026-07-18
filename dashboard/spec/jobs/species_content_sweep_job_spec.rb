require 'rails_helper'

RSpec.describe SpeciesContentSweepJob do
  before { create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin', Confidence: 0.9) }

  it 'queues nothing when every species already has its content' do
    SpeciesInfo.create!(sci_name: 'Erithacus rubecula', description: 'A robin.',
                        fetched_at: Time.current, fetched_ga_at: Time.current, fetched_song_at: Time.current)
    expect { described_class.new.perform }.not_to have_enqueued_job(PrepareSpeciesContentJob)
  end

  it 'queues the species that are missing content' do
    expect { described_class.new.perform }.
      to have_enqueued_job(PrepareSpeciesContentJob).with('Erithacus rubecula')
  end

  it 'clears the stored text when forced, so it is genuinely re-derived' do
    # Without clearing, english_for returns the cached string the instant it is present and the
    # per-species job sees content_ready? and skips — which is exactly how stale descriptions,
    # cached while the model was unavailable, survived every previous attempt to refresh them.
    info = SpeciesInfo.create!(sci_name: 'Erithacus rubecula', description: 'Stale lead paragraph.',
                               fetched_at: Time.current, fetched_ga_at: Time.current,
                               fetched_song_at: Time.current)

    expect { described_class.new.perform(force: true) }.
      to have_enqueued_job(PrepareSpeciesContentJob).with('Erithacus rubecula')
    expect(info.reload.description).to be_nil
    expect(info.fetched_at).to be_nil
  end

  it 'leaves the song alone when forced — a URL does not go stale like model prose' do
    info = SpeciesInfo.create!(sci_name: 'Erithacus rubecula', description: 'x',
                               song_url: 'https://example.org/robin.ogg', fetched_song_at: Time.current)
    described_class.new.perform(force: true)
    expect(info.reload.song_url).to eq('https://example.org/robin.ogg')
  end
end
