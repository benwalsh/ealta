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
    @bootstrap = {
      current_user: user_payload,
      ui_lang:      ui_lang,
      windows:      WINDOWS,
      place:        place_payload,
      favourites:   followed_sci_names,
      site_name:    Station.site_name,
      # nil when the station ships no mark — the masthead then renders the word alone.
      assets:       { mark:     (station_brand_path('mark') if Station.brand_asset('mark')),
                      mark_alt: Station.mark_alt }
    }
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
    # The collage is a FROZEN daily edition — the day's flock packed once and held, so the
    # panel reads like a printed field-guide plate, not a churning dashboard. New birds land
    # only in the live line below; tomorrow brings a fresh plate. Cached by the Dublin date
    # (the packer is date-seeded, so a fixed input is a fixed layout all day).
    edition = Rails.cache.fetch("station-edition-#{now.to_date}", expires_in: 26.hours) do
      Detection.tally_within(current_window)
    end
    @collage = CollagePresenter.new(edition, width: 452, height: 600, top_inset: 4, bottom_inset: 4,
                                             margin: 6, x_bias: 0.82, y_bias: 1.0)
    @species_today = Detection.tally_for.size
    @arrival = latest_arrival
    @status = station_status(now)
    # The footer is a subset of the home page's ambient almanac — the same bilingual
    # line-icon readings — not a parallel set of the panel's own. Place already sits in
    # the header, so drop that one item to avoid saying it twice.
    @almanac = TodayCard.almanac.reject { |item| item[:icon] == 'ti-map-pin' }
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

  # Station.place plus a compact "53.3°N 6.2°W" label for the page footer (the almanac
  # row no longer carries place). Coords from the cached almanac, ENV as the backstop;
  # coords is nil when neither is set, place itself nil when nothing is configured.
  def place_payload
    base = Station.place
    return nil unless base

    coords = Almanac.current[:coords] || {}
    lat = (coords[:lat] || ENV.fetch('BIRD_LAT', nil))&.to_f
    lon = (coords[:lon] || ENV.fetch('BIRD_LON', nil))&.to_f
    base.merge(coords: (lat && lon ? helpers.format_coords(lat, lon) : nil))
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
