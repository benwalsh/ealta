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
      }
    }
  end
end
