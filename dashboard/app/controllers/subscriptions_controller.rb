# Logged-in users manage their own alert subscriptions and how they're delivered.
# Server-rendered + session-authed with Rails CSRF on the forms — the public JSON
# API stays cookie-free; this is the one authenticated write surface (with the
# favourites toggle).
class SubscriptionsController < ApplicationController
  before_action :require_login, except: :unsubscribe

  # "Breaking news" = the urgent, as-it-happens kinds, delivered immediately (a rarity
  # or a first-ever sighting). One opt-in covers all of them; the calmer everyday
  # arrivals are carried by the daily letter's narration instead.
  BREAKING_TYPES = %w[rarity first_ever seasonal].freeze

  def index
    subs = current_user.subscriptions.active
    @follows = subs.where(alert_type: 'species').order(:sci_name)
    @roundup = subs.exists?(alert_type: 'roundup')
    @species = species_options
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
    return redirect_to(account_path) unless Subscription::CADENCES.include?(wanted)

    case type
    when 'species'  then apply_follow_cadence(wanted)
    when 'breaking' then apply_breaking(wanted)
    when 'roundup'  then apply_roundup(wanted)
    end
    redirect_to account_path
  end

  def destroy
    current_user.subscriptions.find(params.expect(:id)).destroy
    redirect_to account_path
  end

  # One-click unsubscribe from an email link — token-authed, no login, idempotent.
  def unsubscribe
    @subscription = Subscription.find_by(token: params[:token])
    @subscription&.update(active: false)
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
