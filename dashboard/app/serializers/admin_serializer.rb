# What the admin console shows — deliberately only two kinds of thing: what an admin can act
# on, and what goes wrong SILENTLY (email delivery and offsite backup are configured-or-not,
# and nothing tells you when they aren't). Counts, adapters and regions were dropped: the
# stats page owns the tallies, and knowing the database is SQLite has never helped anyone at
# 2am. Times cross as ISO strings; BirdName::Name is flattened.
module AdminSerializer
  # Mirrors the DailyEmailSweep schedule in config/recurring.yml — shown so an admin can see
  # when the letter goes without reading the deploy config.
  LETTER_AT = '00:15'.freeze

  module_function

  def health(snapshot)
    listening = snapshot[:listening]
    alerts = snapshot[:alerts]
    species = listening[:last_species]

    {
      listening: {
        freshness:        listening[:freshness],
        last_alive_at:    listening[:last_alive_at]&.iso8601,
        last_heard_at:    listening[:last_heard_at]&.iso8601,
        last_species:     species && { en: species.en, ga: species.ga },
        detections_today: listening[:detections_today],
        species_today:    listening[:species_today],
        # Drives whether the restart control is offered at all — no systemctl or no unit
        # (macOS dev, the cloud mirror) means restarting is not a thing you can do here.
        restartable:      ListenerControl.available?
      },
      alerts:    {
        configured:     alerts[:configured],
        from:           alerts[:from],
        events_pending: alerts[:events_pending]
      },
      # The letter goes out from ONE place: the cloud runs DailyEmailSweep just after midnight
      # station time (config/recurring.yml), the Pi never mails. `sends_here` is what stops the
      # console calling a by-design silence ("no ALERTS_FROM on the Pi") a fault.
      letter:    {
        sends_here: Rails.env.cloud?,
        at:         LETTER_AT,
        zone:       Rails.application.config.time_zone,
        # How many people the letter — and so a blast — actually reaches. Not a vanity tally:
        # the console makes you type this number to confirm a broadcast.
        readers:    Blast.count
      },
      # Litestream backs up the device's SQLite; the cloud is RDS and has no bucket, so only
      # the device should be warned about a missing one.
      backup:    snapshot[:system][:backup].merge(expected: Rails.env.production?),
      station:   {
        language: Station.language,
        options:  Station.languages.map { |code| { code: code, name: Station.language_name(code) } }
      },
      device:    device(snapshot[:device])
    }
  end

  # The wall's vitals. Only two things cross: the plain-English warnings (already words, so the
  # panel never has to know what a throttled bitfield is), and the readings themselves for the
  # times when "everything is fine" isn't enough and you want to see the numbers.
  #
  # `reporting` leads because it qualifies everything after it. A device that stopped reporting
  # an hour ago must not be able to look like one reporting healthy values — so the panel gets
  # told the report is stale rather than being left to infer it from a timestamp it might not
  # render. Times cross as ISO strings; durations as whole seconds, formatted client-side.
  def device(device)
    return { reporting: 'none' } if device.nil? || device[:reporting] == :none

    {
      reporting:   device[:reporting].to_s,
      received_at: device[:received_at]&.iso8601,
      warnings:    device[:warnings],
      version:     { sha: device[:version][:sha], dirty: device[:version][:dirty] },
      uptime:      device[:uptime]&.round,
      panel:       {
        pushed_at: device[:panel][:pushed_at]&.iso8601,
        ran_at:    device[:panel][:ran_at]&.iso8601,
        outcome:   device[:panel][:outcome]
      },
      services:    device[:services],
      # The bucket name is already on `backup`; what's new here is whether the replica was
      # actually reachable when the device last asked.
      litestream:  { at: device[:litestream][:at]&.iso8601, error: device[:litestream][:error] },
      disk:        { free_mb: device[:disk][:free_mb], total_mb: device[:disk][:total_mb] },
      cpu_temp_c:  device[:cpu_temp_c],
      power:       device[:power],
      mic_name:    device[:mic_name]
    }
  end
end
