# Regenerates the home page's "today" note off the request path.
#
# This used to happen INSIDE GET /api/overview: the note goes stale every 30 minutes, and
# whichever visitor arrived first after that paid for the regeneration in their page load —
# DailyFacts (a per-species walk over the day) and then DayNarrator, which on the cloud is a
# Bedrock call. So one load in every thirty minutes was seconds slower than the rest, which is
# the worst shape a slowness can have: too rare to reproduce on demand, common enough to be
# what someone remembers about the site. A Lighthouse run caught one — /api/overview at
# 1,014ms, with every collage image behind it, because the SPA cannot draw a bird until the
# overview lands.
#
# Same move as PrepareSpeciesContentJob: the work is identical whenever it runs, so nobody's
# page load should be the thing that runs it. The request now only NOTICES the staleness and
# enqueues; it serves the note it already had, at most a few seconds older than before.
class WarmTodaySummaryJob < ApplicationJob
  queue_as :default

  def perform
    # Re-check rather than trusting the enqueue-time snapshot: several visitors can arrive
    # inside the same stale window, and the guard in the controller narrows that race without
    # closing it. Whoever gets here first does the work; the rest return immediately.
    return unless TodaySummary.stale?

    # enrich: false, exactly as the request path used — re-stitch the note from bundles that
    # already exist, never block on live sourcing. Building bundles for new arrivals stays the
    # timer's and the ingest's job.
    TodaySummary.refresh_if_stale(enrich: false)
  rescue StandardError => e
    # A failed narration must not retry-storm the queue or lose the last-good note: TodaySummary
    # keeps the previous cache on failure, and the next page load re-enqueues this anyway.
    Rails.logger.warn("WarmTodaySummaryJob: #{e.class}: #{e.message}")
  end
end
