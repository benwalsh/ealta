# Logged-in users manage their own alert subscriptions and how they're delivered.
# Server-rendered + session-authed with Rails CSRF on the forms — the public JSON
# API stays cookie-free; this is the one authenticated write surface (with the
# favourites toggle).
class SubscriptionsController < ApplicationController
  before_action :require_login, except: %i[unsubscribe unsubscribe_letter]
  # The email unsubscribe links are hit by mailbox providers doing a one-click POST
  # (RFC 8058), which carries no CSRF token — token in the path is the auth instead.
  skip_forgery_protection only: %i[unsubscribe unsubscribe_letter]

  # "Breaking news" = the urgent, as-it-happens kinds, delivered immediately (a rarity
  # or a first-ever sighting). One opt-in covers all of them; the calmer everyday
  # arrivals are carried by the daily letter's narration instead.
  BREAKING_TYPES = %w[rarity first_ever seasonal].freeze

  # HTML boots the React SPA with the account panel pre-opened (a hard nav to /account);
  # JSON feeds that panel. The follow list isn't serialized — the SPA already holds it.
  def index
    respond_to do |format|
      format.html do
        @bootstrap = spa_bootstrap(open_panel: 'account')
        render 'collage/show', layout: 'editorial'
      end
      format.json { render json: AccountSerializer.call(current_user) }
    end
  end

  # Add a followed species from the picker; it inherits the user's current follow
  # cadence so a new follow behaves like the others.
  def create
    sub = current_user.subscriptions.find_or_initialize_by(subscription_params)
    sub.cadence = current_follow_cadence if sub.new_record?
    sub.update(active: true) # reactivates a previously-unsubscribed row, or creates
    redirect_to account_path
  end

  # Set how a channel is delivered. 'species' bulk-sets every follow (they stay
  # followed, just silent); 'breaking' flips all the newsworthy kinds to immediate or
  # removes them; 'roundup' is the daily letter (always digest). 'off' clears.
  def cadence
    type = params[:alert_type]
    wanted = params[:cadence]
    unless Subscription::CADENCES.include?(wanted)
      return respond_to do |format|
        format.html { redirect_to account_path }
        format.json { render json: { ok: false }, status: :unprocessable_content }
      end
    end

    case type
    when 'species'  then apply_follow_cadence(wanted)
    when 'breaking' then apply_breaking(wanted)
    when 'roundup'  then apply_roundup(wanted)
    end

    respond_to do |format|
      format.html { redirect_to account_path }
      format.json do
        render json: { ok: true, roundup: current_user.subscriptions.active.exists?(alert_type: 'roundup') }
      end
    end
  end

  def destroy
    current_user.subscriptions.find(params.expect(:id)).destroy
    redirect_to account_path
  end

  # One-click unsubscribe from a single-bird alert — token-authed, no login, idempotent.
  # A GET (the link in the email body) shows the confirmation page; a POST (a mailbox
  # provider's one-click, List-Unsubscribe-Post) just needs a 2xx.
  def unsubscribe
    sub = Subscription.find_by(token: params[:token])
    sub&.update(active: false)
    @unsubscribed = sub.present?
    head :ok if request.post?
  end

  # One-click unsubscribe from the daily letter — per-user token, so it drops the reader
  # out of the letter entirely (roundup + any digesting follow), without unfollowing.
  def unsubscribe_letter
    user = User.find_by(letter_token: params[:token])
    user&.unsubscribe_from_letter!
    @unsubscribed = user.present?
    return head :ok if request.post?

    render :unsubscribe
  end

  private

  def apply_follow_cadence(wanted)
    # One statement; `wanted` is validated in `cadence`, so skipped per-row validations
    # cost nothing.
    # rubocop:disable Rails/SkipsModelValidations
    current_user.subscriptions.where(alert_type: 'species').update_all(cadence: wanted)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Breaking on → every newsworthy kind immediate; off → remove them.
  def apply_breaking(wanted)
    if wanted == 'off'
      current_user.subscriptions.where(alert_type: BREAKING_TYPES, sci_name: nil).destroy_all
    else
      BREAKING_TYPES.each do |type|
        current_user.subscriptions.find_or_initialize_by(alert_type: type, sci_name: nil).
          update!(active: true, cadence: 'immediate')
      end
    end
  end

  def apply_roundup(wanted)
    if wanted == 'off'
      current_user.subscriptions.where(alert_type: 'roundup', sci_name: nil).destroy_all
    else
      current_user.subscriptions.find_or_initialize_by(alert_type: 'roundup', sci_name: nil).
        update!(active: true, cadence: 'digest') # the daily letter only ever arrives by digest
    end
  end

  def subscription_params
    params.expect(subscription: %i[alert_type sci_name])
  end

  def current_follow_cadence
    current_user.subscriptions.find_by(alert_type: 'species')&.cadence || 'digest'
  end

  # The 206 Irish (BoCCI) species, bilingual, sorted by English name — a sane
  # picker rather than all ~6000 BirdNET species.
  def species_options
    Conservation.species.map { |sci| [sci, BirdName.lookup(sci)] }.
      sort_by { |_sci, name| name.en }
  end
end
