class CollageController < ApplicationController
  # The four cards /kiosk cycles through. /station shows only the first (collage).
  KIOSK_SCREENS = %w[collage stats focus general].freeze
  # How long each kiosk card holds before the next fades in (seconds). Floor of 8s
  # so an over-eager env value can't strobe the display.
  KIOSK_DWELL_SECONDS = [ENV.fetch('KIOSK_DWELL_SECONDS', 30).to_i, 8].max
  # A heartbeat within this reads "listening"; older, "recorder quiet since…".
  STATION_FRESH = 30.minutes

  # / — the React SPA host. The editorial layout renders only the mount point; all
  # view data comes from /api/*. The first paint is seeded by a small bootstrap blob
  # so the chrome (auth, language, brand) needs no round-trip.
  layout 'editorial', only: :show

  def show
    @bootstrap = spa_bootstrap
  end

  # The bare collage SVG, no chrome — what the e-ink shooter screenshots.
  def panel
    return head :not_found unless Station.screen

    @collage = collage
    render partial: 'panel', layout: false
  end

  # A standalone page that mocks the physical panel: it fetches /panel and dithers
  # it to the Spectra-6 palette client-side (see the view). No @collage needed here.
  def emulator
    return head :not_found unless Station.screen

    render layout: false
  end

  # /kiosk — no chrome, no nav: the four cards, cycling client-side (a smooth
  # cross-fade, no reload flash), for a passive monitor/iPad in portrait or
  # landscape. Full colour — a real screen, not the e-ink panel.
  def kiosk
    load_cards
    @dwell_seconds = KIOSK_DWELL_SECONDS
    render layout: false
  end

  # /station — the clean screen the e-ink panel shows and the shooter captures (its
  # dimensions come from station.yml `screen:`): a daily printed-broadside edition — the
  # frozen collage plate, a live line (species count + the latest arrival), the ambient
  # almanac, and a status marker with an honest "updated" stamp (not a live clock). No
  # frame, no e-ink filter — the panel dithers it itself. 404 when the station has no
  # screen configured: there is no glass to render for.
  def station
    return head :not_found unless Station.screen

    load_station
    render layout: false
  end

  # /station/preview — the same screen wrapped in the timber frame + a CSS/SVG e-ink
  # emulation, so a desktop browser previews what reads on the physical panel.
  def station_preview
    return head :not_found unless Station.screen

    load_station
    render layout: false
  end

  private

  def load_station
    now = Time.current
    @updated_at = now
    # The panel's stamp is coarsened to the half hour ON PURPOSE. The shooter skips the refresh
    # when the rendered image is byte-identical (shoot.py hashes the screenshot), and the
    # Impression has no partial update — every push is a full ~30–40s flash. A minute-precise
    # clock would differ on every 5-minute cycle and force that flash ~288 times a day to say
    # nothing new. At half-hour resolution the image holds still unless something real changes,
    # and a stopped station is still obvious at a glance.
    @printed_at = now.change(min: now.min < 30 ? 0 : 30, sec: 0)
    @printed_on = TodayCard.stamp_date(@printed_at)
    # The collage is a FROZEN daily edition — the day's flock packed once and held, so the
    # panel reads like a printed field-guide plate, not a churning dashboard. New birds land
    # only in the live line below; tomorrow brings a fresh plate. Cached by the Dublin date
    # (the packer is date-seeded, so a fixed input is a fixed layout all day).
    edition = Rails.cache.fetch("station-edition-#{now.to_date}", expires_in: 26.hours) do
      Detection.tally_within(current_window)
    end
    # Sized to the plate box the four-zone panel leaves (480×800 less the padding, the news
    # line, the almanac bar and the footer), so the flock fills it rather than floating in it.
    @collage = CollagePresenter.new(edition, width: 428, height: 578, top_inset: 4, bottom_inset: 4,
                                             margin: 6, x_bias: 0.82, y_bias: 1.0)
    @species_today = Detection.tally_for.size
    @arrival = latest_arrival
    @status = station_status(now)
    # The panel's bar is the simplified almanac — temperature, moon, sunrise, sunset — as four
    # marks read at a glance. Place is dropped (self-evident on the wall it hangs on), but the
    # TIDE gets its own line rather than being squeezed in: this is the device actually in the
    # house on the coast, and the turning point names the local beach, which no other surface
    # tells you.
    items = TodayCard.almanac.reject { |item| item[:icon] == 'ti-map-pin' }
    @tide = items.find { |item| item[:icon] == 'ti-ripple' }
    @almanac = items - [@tide].compact
  end

  # The most recent species to make its FIRST appearance today, with that time — the one
  # addition worth a line while the frozen plate stays put. nil until something is heard.
  def latest_arrival
    firsts = Detection.on_date(Time.zone.today).group(:Sci_Name).minimum(Arel.sql(Detection.when_sql))
    return nil if firsts.blank?

    sci, whenstr = firsts.max_by { |_sci, w| w.to_s }
    { name: BirdName.lookup(sci), at: Time.zone.parse(whenstr.to_s) }
  rescue ArgumentError, TypeError
    nil
  end

  # Is the recorder alive? The freshest of a heartbeat tick or a detection — "listening" if
  # recent, else quiet-since. Same signal as AdminHealth, in the wall's calmer voice.
  def station_status(now)
    tick  = Heartbeat.last_at
    heard = Detection.where.not(Date: nil).where.not(Time: nil).order(Date: :desc, Time: :desc).first&.heard_at
    alive = [tick, heard].compact.max
    { listening: alive.present? && alive > now - STATION_FRESH, since: alive }
  end

  def collage
    CollagePresenter.new(Detection.tally_within(current_window))
  end

  # Everything the four kiosk cards need in one pass.
  def load_cards
    tally = Detection.tally_within(current_window)
    @screens = KIOSK_SCREENS
    @collage = CollagePresenter.new(tally, width: 900, height: 620)
    @species_today = Detection.tally_for.size
    @detections_today = Detection.today.count
    @species_all_time = Detection.life_list.size
    @detections_all_time = Detection.count
    @recent = tally.sort_by { |t| t.last_time.to_s }.last(6).reverse
    @featured = station_feature(tally)
    @periods = Detection.by_period
    @moon = MoonPhase.for
  end

  # The panel's one language (:ga or :en) — an admin sets it; every string on the screen
  # follows it, so the wall never mixes languages the way it used to.
  def station_lang
    Station.language
  end
  helper_method :station_lang

  # Pick the panel's language from a bilingual { en:, ga: } hash, English as the backstop.
  def station_text(hash)
    return nil if hash.nil?

    hash[station_lang] || hash[:en]
  end
  helper_method :station_text

  # The card's featured bird: most recently heard, ties broken by call count.
  def station_feature(tally)
    return nil if tally.empty?

    tally.max_by { |item| [station_time(item.last_time).to_i, item.count] }
  end

  def station_time(value)
    return nil unless value

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
  helper_method :station_time
end
