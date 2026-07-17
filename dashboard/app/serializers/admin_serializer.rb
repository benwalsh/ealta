# Makes AdminHealth.snapshot JSON-safe for the admin panel and adds the station-language
# block the language control needs. The snapshot carries Time objects (last_heard_at,
# last_alive_at, last_event.at) and a BirdName::Name (last_species) that must be flattened
# before they cross to JSON; everything else passes through unchanged.
module AdminSerializer
  module_function

  def health(snapshot)
    listening = snapshot[:listening]
    alerts = snapshot[:alerts]
    event = alerts[:last_event]
    species = listening[:last_species]

    {
      listening: listening.merge(
        last_heard_at: listening[:last_heard_at]&.iso8601,
        last_alive_at: listening[:last_alive_at]&.iso8601,
        last_species:  species && { sci: species.sci, en: species.en, ga: species.ga }
      ),
      alerts:    alerts.merge(
        last_event: event&.merge(at: event[:at].iso8601)
      ),
      system:    snapshot[:system],
      station:   {
        language: Station.language,
        options:  Station.languages.map { |code| { code: code, name: Station.language_name(code) } }
      }
    }
  end
end
