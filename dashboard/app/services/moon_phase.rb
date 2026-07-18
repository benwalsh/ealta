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

  Phase = Data.define(:name, :name_ga, :illumination, :emoji, :waxing, :path, :shadow)

  class << self
    def for(date = Date.current)
      age = (date - KNOWN_NEW_MOON).to_f % SYNODIC
      index = ((age / SYNODIC) * 8).round % 8
      illumination = (((1 - Math.cos(2 * Math::PI * age / SYNODIC)) / 2) * 100).round
      waxing = age < (SYNODIC / 2)
      Phase.new(name: NAMES[index], name_ga: NAMES_GA[index], illumination: illumination,
                emoji: EMOJI[index], waxing: waxing,
                path: path(illumination, waxing), shadow: shadow(illumination, waxing))
    end

    # The UNLIT part of the disc — the one the views actually ink. On a paper-white ground
    # (and on the panel's dithered e-ink) ink reads as dark, so filling the LIT region draws a
    # photographic negative: a full moon comes out solid black and a new moon as an empty ring.
    # Inking the shadow instead gives the printed-almanac reading — new moon solid, full moon
    # open, the lit limb always the colour of the page.
    #
    # The shadow of a phase is exactly the lit region of its complement (same terminator, other
    # limb), so it needs no new geometry: 25% waxing is lit on the right, and its shadow is the
    # 75%-waning shape on the left. nil at full moon — nothing is dark, so only the outline
    # circle is drawn.
    def shadow(illumination, waxing)
      path(100 - illumination, !waxing)
    end

    # The LIT part of the disc as an SVG path, in a 24×24 icon box — so the almanac and the
    # panel draw the moon's real shape instead of one fixed crescent that is wrong at seven
    # phases out of eight. Ruby computes, the view draws (the collage's arrangement too).
    # Emoji would be the easy way and are forbidden here: line-drawn ink, not glyphs.
    #
    # Geometry: the terminator is the half-ellipse x = s·√(R²−y²) with s = 1 − 2·illumination,
    # so the lit region is bounded by the outer limb on the lit side and that ellipse. Two arcs
    # close it. s > 0 gives a crescent (terminator bulges toward the lit limb), s < 0 a gibbous
    # one; at the quarters s = 0 and the ellipse degenerates to the straight line SVG draws for
    # rx = 0. Northern hemisphere: waxing lights the RIGHT limb, waning the left.
    #
    # nil at new moon — nothing is lit, so the view draws the empty disc outline alone.
    def path(illumination, waxing, radius: 9, cx: 12, cy: 12)
      return nil if illumination <= 0

      s = 1 - (2 * (illumination / 100.0))
      lit = waxing ? 1 : -1
      # Arc bottom→top passes +x when sweep=0, −x when sweep=1; aim it at x = lit·s·R.
      limb_sweep = waxing ? 1 : 0
      term_sweep = (lit * s).positive? ? 0 : 1
      rx = (s.abs * radius).round(3)

      "M#{cx},#{cy - radius} " \
        "A#{radius},#{radius} 0 0 #{limb_sweep} #{cx},#{cy + radius} " \
        "A#{rx},#{radius} 0 0 #{term_sweep} #{cx},#{cy - radius} Z"
    end
  end
end
