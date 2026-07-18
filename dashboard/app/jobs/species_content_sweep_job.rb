# Walks the life list and makes sure every species has its modal content, enqueuing one
# PrepareSpeciesContentJob per bird so each is a small, independently retryable unit rather
# than one long job that loses everything if a single Wikipedia lookup falls over.
#
# This is the admin console's hands: ECS Express Mode exposes no ECS Exec
# (aws_ecs_express_gateway_service has no enable_execute_command), so there is no shell into
# the running cloud task and `rails ealta:warm_species` cannot be run there by hand. The same
# sweep therefore has to be reachable from /admin. The rake task remains the local equivalent.
#
# `force:` clears the stored text first. That is the only way to genuinely re-derive, because
# english_for/irish_for return whatever is cached the moment it is present — the per-species
# job would otherwise look at a stale row, see content_ready?, and skip it. This is what
# refreshes descriptions cached back when the model was briefly unavailable and frozen since.
class SpeciesContentSweepJob < ApplicationJob
  queue_as :default

  def perform(force: false)
    scis = Detection.life_list.filter_map(&:sci_name).uniq
    return 0 if scis.empty?

    clear(scis) if force
    due = force ? scis : SpeciesInfo.missing_content(scis)
    due.each { |sci| PrepareSpeciesContentJob.perform_later(sci) }
    Rails.logger.info("SpeciesContentSweepJob: queued #{due.size} of #{scis.size} species (force: #{force})")
    due.size
  end

  private

  # Blank the derived text so it is actually re-derived. The song is left alone: it is a URL
  # rather than model output, so it does not go stale the way a description does.
  def clear(scis)
    SpeciesInfo.where(sci_name: scis).find_each do |info|
      info.update(description: nil, description_ga: nil, fetched_at: nil, fetched_ga_at: nil)
    end
  end
end
