# Runs after each ingest batch: turns the day's *notable* birds into fire-once
# `events`, then emails the matching subscribers. Best-effort and queue-free — a
# send failure leaves the event unsent, so the next ingest tick retries it.
#
# It does NOT re-derive what's notable. DailyFacts — the one facts engine behind the
# Inky panel and the website — already flags all-time-firsts, seasonal returns and
# local rarities, importance-scored and young-station-damped. The alerts read those
# same flags, so panel, site and email share one definition of "first" and "rare".
#
# `upsert_all` skips ActiveRecord callbacks, so this is the batch-level "after_create
# :notify!" the ingest can't express directly.
class AlertEngine
  # DailyFacts item flag → the standing-rule alert it fires. most_common /
  # unusual_volume / routine are texture, not news, so they never alert.
  FLAG_ALERTS = {
    'all_time_first' => 'first_ever',
    'year_first'     => 'seasonal',
    'rare_local'     => 'rarity'
  }.freeze

  # First-ever and seasonal-return only mean something once there's a real baseline:
  # in a station's first year nearly everything is a "first". Local rarity self-gates
  # on its own baseline (RARE_MIN_AGE_DAYS), and follows are an explicit request, so
  # both fire from day one; these two wait for the station to mature.
  BASELINE_GATED = %w[first_ever seasonal].freeze

  class << self
    # The arg is kept for the ingest call site; the day's facts decide what fires,
    # not the batch, so a species that turned notable earlier isn't missed.
    def scan(_sci_names = nil)
      new.run
    end
  end

  def run
    record_events
    deliver_pending
  end

  private

  def record_events
    facts = DailyFacts.for
    mature = facts[:station_age_days] >= DailyFacts::YOUNG_STATION_DAYS
    facts[:items].each do |item|
      sci = item[:sci_name]
      item[:flags].each do |flag|
        type = FLAG_ALERTS[flag]
        next unless type
        next if BASELINE_GATED.include?(type) && !mature

        record(type, sci)
      end
      record('species', sci) if subscribed?(sci)
    end
  end

  # Immediate delivery only — digest-cadence subscribers are picked up by the daily
  # DailyLetter run instead, and 'off' never emails. An event with no immediate
  # recipients settles at once (nothing to send now); the digest reads it later
  # straight from the day's events, so notified_at only ever tracks immediate sends.
  def deliver_pending
    Event.pending.find_each do |event|
      recipients = subscriptions_for(event).immediate
      delivered = recipients.map { |sub| Notifier.deliver(event:, subscription: sub) }
      # Mark done only if every recipient succeeded (none = nothing to retry); a
      # failure leaves notified_at nil so the next tick retries.
      event.mark_notified! if delivered.all?
    end
  end

  def record(type, sci)
    Event.find_or_create_by!(event_type: type, sci_name: sci, occurred_on: Date.current)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent ingest already recorded it — fine, it's fire-once by design.
  end

  def subscribed?(sci)
    Subscription.for_species(sci).exists?
  end

  def subscriptions_for(event)
    if event.event_type == 'species'
      Subscription.for_species(event.sci_name)
    else
      Subscription.of_type(event.event_type)
    end
  end
end
