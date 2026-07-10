# On-demand facts & folklore for one bird — the "look it up now" the card offers a
# signed-in viewer when a species hasn't been enriched by the daily sweep yet. Session +
# CSRF like favourites/account (NOT the cookie-free /api surface), because it triggers a
# real Claude sourcing run and so must be authenticated, never cached.
#
# It reuses a current bundle if one exists (cheap, and the daily backoff still owns the
# automated cadence); otherwise it sources once, now, storing the bundle so every later
# viewer — signed in or not — gets it for free from the species API.
class EnrichmentController < ApplicationController
  before_action :require_login

  def create
    sci = params.expect(:sci)
    bundle = EnrichmentBundle.current(sci)
    bundle = Enrichment::Builder.build_one(date: Date.current, sci_name: sci) if bundle&.to_display.nil?
    render json: { enrichment: bundle&.to_display }
  end
end
