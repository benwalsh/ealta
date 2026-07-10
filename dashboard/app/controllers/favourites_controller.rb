# Follow / unfollow a species straight from the SPA — the authenticated JSON
# sibling of the server-rendered /account page. A "follow" is just a species
# Subscription, so the very same row lists on /account and fires the same
# AlertEngine notification the next time the bird is heard. Session + CSRF, like
# the sign-in/out posts; deliberately NOT under /api (that surface is cookie-free
# and cacheable — this one is per-user and must never be cached).
class FavouritesController < ApplicationController
  before_action :require_login

  def create
    sub = current_user.subscriptions.find_or_initialize_by(alert_type: 'species', sci_name: sci_name)
    # A new follow inherits how the user's other follows are delivered, so the one
    # "Birds you follow" control on /account keeps meaning what it says.
    sub.cadence = follow_cadence if sub.new_record?
    sub.update!(active: true)
    render json: { sci_name: sci_name, following: true }
  end

  def destroy
    current_user.subscriptions.
      find_by(alert_type: 'species', sci_name: sci_name)&.update!(active: false)
    render json: { sci_name: sci_name, following: false }
  end

  private

  def sci_name
    params.expect(:sci_name)
  end

  def follow_cadence
    current_user.subscriptions.find_by(alert_type: 'species')&.cadence || 'digest'
  end
end
