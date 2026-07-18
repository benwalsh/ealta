# Prepares everything the species modal shows, so opening it is a pure database read.
#
# The modal used to build itself on the click: a Wikipedia fetch, an LLM summary, an LLM
# translation (which WAITS on the summary — it translates it) and a Commons audio lookup, all
# in series. Measured at ~11s for the first person to open a bird and ~0.1s for everyone
# after, because the results cache forever. The work is identical whenever it runs, so it
# runs here instead — enqueued the moment the station hears a species (IngestController), long
# before anyone clicks.
#
# CLOUD ONLY, and structurally so: the only caller is the ingest endpoint, which 404s unless
# CLOUD_INGEST_TOKEN is set — and that is set in the cloud alone. The Pi shows neither the
# modal nor the Journal and has no model configured, so it neither needs this nor could run it.
class PrepareSpeciesContentJob < ApplicationJob
  queue_as :default

  def perform(sci)
    # A species can be enqueued twice — two batches arriving before the first job runs — so
    # re-check here rather than trusting the enqueue-time snapshot. Without this a duplicate
    # would pay for the same pair of model calls a second time.
    return if SpeciesInfo.content_ready?(sci)

    name = BirdName.lookup(sci)
    # Order matters: the Irish is a translation of the English summary, so English first.
    SpeciesInfo.english_for(sci, name.en)
    SpeciesInfo.irish_for(sci, name.ga)
    SongSample.url_for(sci)
  rescue StandardError => e
    # One bird's bad article must not poison the queue. The modal still works — it just falls
    # back to fetching on the click, exactly as before — and the next detection re-enqueues.
    Rails.logger.warn("PrepareSpeciesContentJob: #{sci} failed (#{e.class}: #{e.message})")
  end
end
