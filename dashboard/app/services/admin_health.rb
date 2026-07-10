# The admin "is the box alive?" snapshot — everything the health panel shows,
# computed in one place so the view only prints. Read-only; safe to call on every
# admin page load.
#
# Liveness keys off the listener's HEARTBEAT — a tick written every listening cycle, even
# quiet ones (see Heartbeat / listener). So the dot reflects "is the mic → BirdNET loop
# running", which a genuinely quiet night no longer dims: a quiet spell still ticks, only
# a stalled feed goes dark. "Last heard" is reported alongside as activity, not liveness.
# Where no ticks exist yet (the cloud mirror, which doesn't sync them; or a pre-upgrade
# box), it falls back to the old last-heard proxy so the panel still says something.
class AdminHealth
  FRESH = 30.minutes  # green: ticked recently, the loop is running
  QUIET = 6.hours     # amber: no tick lately — likely stalled

  class << self
    def snapshot(now: Time.current)
      new(now).snapshot
    end

    # Public liveness only — :listening / :offline — cheap enough for every page load
    # (one heartbeat read + one detection read; no alerts/system queries). Offline only
    # once nothing — heartbeat or detection — has happened for QUIET, so a quiet spell
    # stays "listening", not a false alarm.
    def status(now: Time.current)
      new(now).status
    end
  end

  def initialize(now)
    @now = now
  end

  def snapshot
    { listening: listening, alerts: alerts, system: system }
  end

  def status
    %i[stale none].include?(freshness(Heartbeat.last_at, latest_detection&.heard_at)) ? :offline : :listening
  end

  private

  def latest_detection
    Detection.where.not(Date: nil).where.not(Time: nil).order(Date: :desc, Time: :desc).first
  end

  def listening
    last = latest_detection
    heard = last&.heard_at
    alive = Heartbeat.last_at
    {
      last_heard_at:       heard,
      last_heard_ago:      heard && (@now - heard),
      last_alive_at:       alive,
      last_alive_ago:      alive && (@now - alive),
      freshness:           freshness(alive, heard),
      last_species:        last && BirdName.lookup(last.Sci_Name),
      detections_today:    Detection.today.count,
      detections_all_time: Detection.count,
      species_today:       Detection.tally_for.size,
      species_all_time:    Detection.life_list.size
    }
  end

  # fresh / quiet / stale — from whichever is more recent, a heartbeat or a detection
  # (both prove the loop ran). The heartbeat is what keeps a genuinely quiet spell green;
  # a detection alone still works where ticks aren't present (cloud mirror / pre-upgrade).
  # Only when neither has happened lately is the feed actually stalled. None if never.
  def freshness(alive, heard)
    signal = [alive, heard].compact.max
    return :none unless signal

    ago = @now - signal
    return :fresh if ago <= FRESH
    return :quiet if ago <= QUIET

    :stale
  end

  def alerts
    last = Event.order(created_at: :desc).first
    {
      configured:     ENV['ALERTS_FROM'].present?,
      from:           ENV.fetch('ALERTS_FROM', nil),
      following:      Subscription.active.where(alert_type: 'species').count,
      standing_rules: Subscription.active.where.not(alert_type: 'species').count,
      events_total:   Event.count,
      events_pending: Event.pending.count, # unsent backlog — should trend to 0
      last_event:     last && { type: last.event_type, name: BirdName.lookup(last.sci_name).en, at: last.created_at }
    }
  end

  def system
    {
      env:        Rails.env,
      adapter:    ActiveRecord::Base.connection.adapter_name,
      site_url:   ENV.fetch('SITE_URL', nil),
      llm_region: ENV.fetch('BEDROCK_REGION', nil),
      # Offsite backup is Litestream (continuous → S3/B2); "configured" means the bucket is set.
      # There's no "backup now" button — replication is always-on when configured.
      backup:     { configured: ENV['LITESTREAM_BUCKET'].present?, bucket: ENV['LITESTREAM_BUCKET'].presence }
    }
  end
end
