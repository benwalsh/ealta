# The moon's phase for a given date — a pure astronomical calculation (no API),
# since the phase is the same the world over. Good enough for a wall display:
# the age since a known new moon, folded over the synodic month, gives both a
# named phase and an illumination percentage.
class MoonPhase
  SYNODIC = 29.530588853                 # days between new moons
  KNOWN_NEW_MOON = Date.new(2000, 1, 6)  # a reference new moon
  NAMES = [
    'New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
    'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent'
  ].freeze
  # Irish names, same order, per the National Terminology Database (téarma.ie):
  # scothlán = gibbous, corrán = crescent, ag líonadh = waxing, ag caitheamh =
  # waning, an chéad/dheireanach cheathrú = first/last quarter.
  NAMES_GA = [
    'Gealach nua', 'Corrán ag líonadh', 'An chéad cheathrú', 'Scothlán ag líonadh',
    'Gealach lán', 'Scothlán ag caitheamh', 'An cheathrú dheireanach', 'Corrán ag caitheamh'
  ].freeze
  # Unicode moon glyphs, one per named phase (same order as NAMES). Reads in full
  # colour on a monitor (kiosk); on the Spectra-6 panel it dithers, which the
  # /station preview deliberately shows.
  EMOJI = %w[🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘].freeze

  Phase = Data.define(:name, :name_ga, :illumination, :emoji)

  class << self
    def for(date = Date.current)
      age = (date - KNOWN_NEW_MOON).to_f % SYNODIC
      index = ((age / SYNODIC) * 8).round % 8
      illumination = (((1 - Math.cos(2 * Math::PI * age / SYNODIC)) / 2) * 100).round
      Phase.new(name: NAMES[index], name_ga: NAMES_GA[index], illumination: illumination, emoji: EMOJI[index])
    end
  end
end
