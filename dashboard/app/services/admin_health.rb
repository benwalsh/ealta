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
#
# The `device` block is of a different kind from the rest: everything else here is computed
# from data the cloud holds, while that is the wall's own last report about itself (see
# DeviceVital). Its freshness therefore travels with it — see #device.
class AdminHealth
  FRESH = 30.minutes  # green: ticked recently, the loop is running
  QUIET = 6.hours     # amber: no tick lately — likely stalled

  # How stale a vitals report may get before the panel stops treating its figures as current.
  # The device pushes every 15 minutes (ealta-push.timer), so this is two missed rounds plus
  # slack for a slow rural link. Past it the numbers are still shown, but as a last-known
  # reading rather than as the state of the wall — see the `reporting` key below.
  VITALS_FRESH = 40.minutes

  # A panel that hasn't refreshed in this long is worth flagging even though nothing has
  # "failed". Generous on purpose: the shooter legitimately skips whenever the station screen
  # is unchanged, and a quiet winter afternoon can hold the same image for hours. A whole day
  # without pixels reaching the glass is a different thing.
  PANEL_QUIET = 24.hours

  # Below this the SD card is close enough to full that Litestream's shadow WAL and the
  # detections DB start competing for the same last megabytes.
  DISK_LOW = 0.10

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
    { listening: listening, alerts: alerts, system: system, device: device }
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
    # "Last event" is ordered by the day it HAPPENED (occurred_on), not by row-insert time — a
    # backfilled row must never outrank a newer occurrence. This reads the Event log (fire-once
    # alert records), the same source as all of notable (Live / journal / breaking strip); it's
    # written by AlertEngine on /ingest, so it only advances where live ingest runs — a dev box
    # with no push shows a stale last event, the device tracks reality.
    last = Event.order(occurred_on: :desc, id: :desc).first
    {
      configured:     ENV['ALERTS_FROM'].present?,
      from:           ENV.fetch('ALERTS_FROM', nil),
      following:      Subscription.active.where(alert_type: 'species').count,
      standing_rules: Subscription.active.where.not(alert_type: 'species').count,
      events_total:   Event.count,
      events_pending: Event.pending.count, # unsent backlog — should trend to 0
      last_event:     last && { type: last.event_type, name: BirdName.lookup(last.sci_name).en, at: last.occurred_on }
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

  # The physical station's vital signs, as last reported (DeviceVital / birdnet/vitals.py).
  #
  # Everything above this is computed from data the cloud holds itself; this is the one block
  # that is a REPORT — a claim the wall made at some past moment, which may since have stopped
  # being true. So the freshness of the report travels with it. Without that, a station whose
  # power died an hour ago would go on showing its last healthy temperature and its last good
  # backup time forever, and the panel would be lying by omission rather than saying "I have
  # not heard from the wall since 14:05".
  def device
    row = DeviceVital.current
    return { reporting: :none } unless row

    {
      reporting:   report_freshness(row),
      received_at: row.received_at,
      reported_at: row.reported_at,
      version:     { sha: row.git_sha, dirty: row.git_dirty },
      boot_at:     row.boot_at,
      uptime:      row.uptime(now: @now),
      panel:       { ran_at: row.panel_ran_at, pushed_at: row.panel_pushed_at, outcome: row.panel_outcome },
      services:    row.services.presence,
      litestream:  { at: row.litestream_at, error: row.litestream_error },
      disk:        { free_mb: row.disk_free_mb, total_mb: row.disk_total_mb, free_fraction: row.disk_free_fraction },
      cpu_temp_c:  row.cpu_temp_c,
      power:       { now: row.undervoltage_now, since_boot: row.undervoltage_since_boot },
      mic_name:    row.mic_name,
      warnings:    device_warnings(row)
    }
  end

  def report_freshness(row)
    (@now - row.received_at) <= VITALS_FRESH ? :fresh : :stale
  end

  # The vitals worth interrupting someone over, already in words. Two rules hold throughout:
  # a nil is "unknown" and never triggers a warning (best-effort collection means a dev box
  # reports mostly nils, and warning about those would train everyone to ignore this list);
  # and nothing here is ever a raw code — the undervoltage bitfield in particular is decoded on
  # the device precisely so nobody has to remember what 0x50005 means at 2am.
  def device_warnings(row)
    [
      report_stale_warning(row),
      panel_warning(row),
      power_warning(row),
      disk_warning(row),
      replica_warning(row),
      service_warnings(row)
    ].flatten.compact
  end

  # First in the list on purpose: if the wall has gone quiet, every warning below it is about a
  # world that may no longer exist, and this is the one to act on.
  def report_stale_warning(row)
    return nil if report_freshness(row) == :fresh

    "The station last reported #{time_ago_in_words(row.received_at)} ago — " \
      'the readings below are its last known state, not its current one.'
  end

  # The failure the whole exercise is for. E-ink holds its last image with no power at all, so
  # a panel that stopped refreshing at Easter looks exactly like one that refreshed a minute
  # ago. Nothing else on the box reports this.
  def panel_warning(row)
    return 'The panel has never reported a refresh.' if row.panel_pushed_at.nil? && row.panel_ran_at.nil?
    return "The panel refresh last failed (#{row.panel_outcome})." if row.panel_outcome == 'failed'
    return nil if row.panel_pushed_at.nil? || (@now - row.panel_pushed_at) <= PANEL_QUIET

    "The panel has not refreshed in #{time_ago_in_words(row.panel_pushed_at)} — " \
      'what is on the glass may be that old.'
  end

  # Undervoltage matters out of proportion to how minor it sounds: it is a known cause of SD
  # card corruption, which is the exact failure the Litestream restore machinery exists to
  # recover from. Since-boot is reported even when the supply is currently fine, because it is
  # evidence of a marginal supply or cable and it will happen again.
  def power_warning(row)
    return 'The power supply is sagging right now (undervoltage) — this can corrupt the SD card.' if
      row.undervoltage_now
    return nil unless row.undervoltage_since_boot

    'The power supply has sagged at least once since boot. Undervoltage can corrupt the SD card, ' \
      'so the supply or its cable is worth replacing.'
  end

  def disk_warning(row)
    free = row.disk_free_fraction
    return nil if free.nil? || free > DISK_LOW

    "The SD card is #{(100 - (free * 100)).round}% full (#{row.disk_free_mb} MB free)."
  end

  # A backup that stopped is indistinguishable from one that works until the day you need it,
  # which is the day it is too late to find out.
  def replica_warning(row)
    return "The offsite backup could not be checked: #{row.litestream_error}." if row.litestream_error.present?

    nil
  end

  def service_warnings(row)
    stopped = row.failing_services
    looping = row.restarting_services
    [
      stopped.any? ? "Not running: #{stopped.to_sentence}." : nil,
      # Up, and so invisible to every other check — but a service on its two-hundredth start is
      # not a healthy service, it is one failing fast enough that systemd keeps hiding it.
      looping.any? ? "Restarting repeatedly: #{looping.to_sentence}." : nil
    ]
  end

  def time_ago_in_words(moment)
    ActionController::Base.helpers.time_ago_in_words(moment)
  end
end
