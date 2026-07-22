# Renders a bird's illustration the first time the station hears it, in the cloud, and publishes
# it to the CDN bucket — so the collage stops showing a blank for a newly-arrived species without
# anyone running the pipeline by hand. Runs on the worker (the render is a Gemini call + image
# processing), enqueued from IngestController beside PrepareSpeciesContentJob.
#
# CLOUD ONLY, structurally: Illustrations.enabled? is false without the bucket, which only the
# cloud has. The Pi loads finished assets and never reaches here.
class GenerateIllustrationJob < ApplicationJob
  queue_as :illustrations

  def perform(sci, common_name = nil)
    return unless Illustrations.enabled?
    # A species can be enqueued twice (two ingest batches before the first render lands), and a
    # render is expensive, so re-check against the bucket here rather than trusting the enqueue.
    return if Illustrations.exists?(sci)

    Illustrations.generate(sci, common_name)
  rescue StandardError => e
    # One bird's failed render must not wedge the queue. The collage just keeps showing the blank
    # it already showed; the next detection re-enqueues. Logged, never silent.
    Rails.logger.warn("GenerateIllustrationJob: #{sci} failed (#{e.class}: #{e.message})")
  end
end
