# The station's current vital signs — one row, overwritten every push. See the migration for
# why this is its own table rather than more columns on Heartbeat.
#
# Everything is nullable and null means "not known", never "zero" or "false". That distinction
# is the whole point on a best-effort collector: a dev box with no vcgencmd reports unknown
# power, and a panel that says "power fine" because it read a null as false would be worse than
# one that says nothing.
class DeviceVital < ApplicationRecord
  # The upsert conflict target. Not tenancy — the cloud mirrors exactly one wall — just a
  # stable handle so "the row" is a thing the database can name.
  STATION_KEY = 'station'.freeze

  # A service that has restarted this many times is not a service that is up, it is one failing
  # fast enough that systemd keeps putting it back. Deliberately well above the handful of
  # restarts a normal week of reboots and redeploys produces.
  RESTART_ALARM = 20

  # Only what the device is allowed to say about itself. Anything else in the payload is
  # dropped rather than stored: the columns are the contract, and a Pi running an older or
  # newer vitals.py must never be able to widen it.
  REPORTED = %w[
    reported_at git_sha git_dirty boot_at
    panel_ran_at panel_pushed_at panel_outcome
    services litestream_at litestream_error
    disk_free_mb disk_total_mb cpu_temp_c
    undervoltage_now undervoltage_since_boot mic_name
  ].freeze

  # `services` has no default anywhere — not on the column and not here. A DB-level one would be
  # illegal on MySQL in any case (error 1101 forbids literal defaults on JSON/TEXT, so it would
  # pass on the device's SQLite and fail the cloud migration), but the deciding reason is
  # meaning: an empty hash would claim the device looked and found no services, when what
  # actually happened is that it could not look at all. The readers below carry the `|| {}`
  # instead, so the distinction survives all the way to storage.

  class << self
    # The row, or nil where the device has never reported (a fresh cloud, or a station still
    # running a vitals-less push.py).
    def current
      find_by(station_key: STATION_KEY)
    end

    # Overwrite the row with this report. received_at is stamped here, from the server's clock,
    # so telemetry staleness is measured against a clock the device cannot get wrong.
    def record!(report, now: Time.current)
      row = find_or_initialize_by(station_key: STATION_KEY)
      row.assign_attributes(report.slice(*REPORTED))
      row.received_at = now
      row.save!
      row
    end
  end

  # How long the box has been up at the moment someone asks — derived rather than stored, so a
  # station that stopped reporting an hour ago doesn't keep accruing uptime it may not have.
  def uptime(now: Time.current)
    boot_at && (now - boot_at)
  end

  # Free space as a fraction, or nil when either half is unknown. Guarded against a zero total
  # because a filesystem read that half-failed should read as unknown, not as a full disk.
  def disk_free_fraction
    return nil if disk_free_mb.nil? || disk_total_mb.to_i.zero?

    disk_free_mb.to_f / disk_total_mb
  end

  # Any unit that isn't running. Timers count: a stopped ealta-frame.timer is exactly how the
  # panel freezes without anything appearing to have failed.
  def failing_services
    (services || {}).reject { |_, unit| unit['state'] == 'active' }.keys
  end

  # Units that are up but have restarted more than a settled box ever should. Not a failure on
  # its own — hence separate from failing_services — but a crash-loop reads as healthy to every
  # other check, so it has to be surfaced somewhere.
  def restarting_services
    (services || {}).select { |_, unit| unit['restarts'].to_i >= RESTART_ALARM }.keys
  end
end
