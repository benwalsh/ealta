require 'net/http'
require 'json'

# The station's surroundings — weather, tide, and coordinates — fetched on a
# schedule and cached to disk. Two hard rules, both from the offline-first keel:
#
#   * `current` NEVER touches the network. Page loads read the last-known cache
#     (which may be hours old on flaky rural broadband — that's fine, it's a wall
#     display, not a forecast service). It is always fast and works offline.
#   * `refresh` (run by the ealta-almanac timer every 30 min) is best-effort:
#     a failure in one source keeps the others and the previous value; a total
#     outage just leaves the last good cache in place.
#
# Weather/sun come from Open-Meteo and the tide from the Marine Institute's ERDDAP
# prediction service (erddap.marine.ie) — both key-free open endpoints, the right trade
# for a box nobody tends. The moon is NOT here: it's a pure calculation (see MoonPhase),
# so it never goes stale and needs no fetch.
class Almanac
  STORE = Rails.root.join('storage/almanac.json')
  HTTP_TIMEOUT = 4
  # ERDDAP (the tide source) can be a touch slower than Open-Meteo; give it more headroom.
  # Still best-effort: a timeout just keeps the last good predictions.
  ERDDAP_TIMEOUT = 8

  # Open-Meteo `weather_code` (WMO) → [English, Irish, emoji] for the facts row.
  # Terms follow Met Éireann's forecast vocabulary (grianmhar, scamallach,
  # ceathanna, báisteach, ceobhrán, modartha, sneachta, stoirm thoirní …) rather
  # than a literal translation.
  WMO = {
    0  => ['clear', 'spéir ghlan', '☀️'],
    1  => ['fair', 'breá', '🌤️'],
    2  => ['partly cloudy', 'scamallach go páirteach', '⛅'],
    3  => ['overcast', 'modartha', '☁️'],
    45 => ['fog', 'ceo', '🌫️'],
    48 => ['freezing fog', 'ceo sioctha', '🌫️'],
    51 => ['light drizzle', 'ceobhrán éadrom', '🌦️'],
    53 => ['drizzle', 'ceobhrán', '🌦️'],
    55 => ['heavy drizzle', 'ceobhrán trom', '🌦️'],
    56 => ['freezing drizzle', 'ceobhrán sioctha', '🌧️'],
    57 => ['freezing drizzle', 'ceobhrán sioctha', '🌧️'],
    61 => ['light rain', 'báisteach éadrom', '🌦️'],
    63 => ['rain', 'báisteach', '🌧️'],
    65 => ['heavy rain', 'báisteach throm', '🌧️'],
    66 => ['freezing rain', 'báisteach shioctha', '🌧️'],
    67 => ['freezing rain', 'báisteach shioctha', '🌧️'],
    71 => ['light snow', 'sneachta éadrom', '🌨️'],
    73 => ['snow', 'sneachta', '🌨️'],
    75 => ['heavy snow', 'sneachta trom', '❄️'],
    77 => ['snow grains', 'gráinní sneachta', '🌨️'],
    80 => ['showers', 'ceathanna', '🌦️'],
    81 => ['showers', 'ceathanna', '🌦️'],
    82 => ['heavy showers', 'ceathanna troma', '🌧️'],
    85 => ['snow showers', 'ceathanna sneachta', '🌨️'],
    86 => ['snow showers', 'ceathanna sneachta', '🌨️'],
    95 => ['thunderstorm', 'stoirm thoirní', '⛈️'],
    96 => ['thunderstorm', 'stoirm thoirní', '⛈️'],
    99 => ['thunderstorm', 'stoirm thoirní', '⛈️']
  }.freeze
  # Tide turning point → [English, Irish] (Lán mara = high water, Lag trá = ebb).
  TIDE_LABELS = { high: ['High tide', 'Lán mara'], low: ['Low tide', 'Lag trá'] }.freeze
  # The tide comes from the Marine Institute's official prediction dataset
  # (IMI_TidePrediction_HighLow on erddap.marine.ie) — authoritative Irish high/low water
  # TIMES, no API key, an open ERDDAP endpoint. These are its 38 prediction stations with
  # their exact positions and a bilingual display name; `nearest_tide_station` picks the one
  # closest to us and we ask ERDDAP for that station's predictions. `id` is the dataset's
  # stationID. Irish names are given where established (proper nouns; ga falls back to en).
  ERDDAP_BASE = 'https://erddap.marine.ie/erddap/tabledap/IMI_TidePrediction_HighLow.json'.freeze
  TIDE_STATIONS = [
    { id: 'Achill_Island', en: 'Achill Island', ga: 'Acaill', lat: 53.9522, lon: -10.1016 },
    { id: 'Aranmore', en: 'Aranmore', ga: 'Árainn Mhór', lat: 54.9896, lon: -8.49562 },
    { id: 'Arklow', en: 'Arklow', ga: 'An tInbhear Mór', lat: 52.792046, lon: -6.145231 },
    { id: 'Ballycotton', en: 'Ballycotton', ga: 'Baile Choitín', lat: 51.82776, lon: -8.0007 },
    { id: 'Ballyglass', en: 'Ballyglass', ga: 'An Baile Glas', lat: 54.253, lon: -9.89 },
    { id: 'Bray_Harbour', en: 'Bray', ga: 'Bré', lat: 53.2191, lon: -6.0901 },
    { id: 'Buncranna', en: 'Buncrana', ga: 'Bun Cranncha', lat: 55.126617, lon: -7.464125 },
    { id: 'Carrigaholt', en: 'Carrigaholt', ga: 'Carraig an Chabhaltaigh', lat: 52.5965, lon: -9.6812 },
    { id: 'Castletownbere', en: 'Castletownbere', ga: 'Baile Chaisleáin Bhéarra', lat: 51.6496, lon: -9.9034 },
    { id: 'Clare_Island', en: 'Clare Island', ga: 'Cliara', lat: 53.8019, lon: -9.9443 },
    { id: 'Crosshaven', en: 'Crosshaven', ga: 'Bun an Tábhairne', lat: 51.7794, lon: -8.2411 },
    { id: 'Dingle', en: 'Dingle', ga: 'An Daingean', lat: 52.13924, lon: -10.27732 },
    { id: 'Dublin_Port', en: 'Dublin Port', ga: 'Port Bhaile Átha Cliath', lat: 53.34574, lon: -6.22166 },
    { id: 'Dungarvan', en: 'Dungarvan', ga: 'Dún Garbhán', lat: 52.0672, lon: -7.5521 },
    { id: 'Dunmore', en: 'Dunmore East', ga: 'An Dún Mór', lat: 52.14754, lon: -6.99166 },
    { id: 'Fenit', en: 'Fenit', ga: 'An Fhianait', lat: 52.27129, lon: -9.8644 },
    { id: 'Galway', en: 'Galway', ga: 'Gaillimh', lat: 53.26895, lon: -9.04796 },
    { id: 'Howth', en: 'Howth', ga: 'Binn Éadair', lat: 53.39148, lon: -6.0683 },
    { id: 'Inishmore', en: 'Inishmore', ga: 'Inis Mór', lat: 53.126, lon: -9.66 },
    { id: 'Killary_Harbour', en: 'Killary Harbour', ga: 'An Caoláire Rua', lat: 53.6316, lon: -9.9016 },
    { id: 'Killybegs', en: 'Killybegs', ga: 'Na Cealla Beaga', lat: 54.6364, lon: -8.3949 },
    { id: 'Kilrush', en: 'Kilrush', ga: 'Cill Rois', lat: 52.63191, lon: -9.50208 },
    { id: 'Kinsale', en: 'Kinsale', ga: 'Cionn tSáile', lat: 51.6777, lon: -8.446 },
    { id: 'Lahinch', en: 'Lahinch', ga: 'An Leacht', lat: 52.911, lon: -9.3899 },
    { id: 'Letterfrack', en: 'Letterfrack', ga: 'Leitir Fraic', lat: 53.582, lon: -10.0388 },
    { id: 'Malin_Head', en: 'Malin Head', ga: 'Cionn Mhálanna', lat: 55.37168, lon: -7.33432 },
    { id: 'Port_Oriel', en: 'Port Oriel', ga: 'Port Oriel', lat: 53.79899, lon: -6.221713 },
    { id: 'Ringaskiddy', en: 'Ringaskiddy', ga: 'Rinn an Scidí', lat: 51.84, lon: -8.304 },
    { id: 'Roonagh', en: 'Roonagh', ga: 'Rua', lat: 53.76235, lon: -9.90442 },
    { id: 'Rossaveel', en: 'Rossaveel', ga: 'Ros an Mhíl', lat: 53.266926, lon: -9.562056 },
    { id: 'Rosslare', en: 'Rosslare', ga: 'Ros Láir', lat: 52.2546, lon: -6.334861 },
    { id: 'Skerries', en: 'Skerries', ga: 'Na Sceirí', lat: 53.585, lon: -6.108117 },
    { id: 'Sligo', en: 'Sligo', ga: 'Sligeach', lat: 54.3046, lon: -8.5689 },
    { id: 'Tom_Clarke_Bridge', en: 'Tom Clarke Bridge', ga: 'Droichead Tom Clarke', lat: 53.346233, lon: -6.227383 },
    { id: 'Tory_Island', en: 'Tory Island', ga: 'Toraigh', lat: 55.2508, lon: -8.1962 },
    { id: 'Union_Hall', en: 'Union Hall', ga: 'Bréantrá', lat: 51.559, lon: -9.1335 },
    { id: 'Wexford', en: 'Wexford', ga: 'Loch Garman', lat: 52.33852, lon: -6.4589 },
    { id: 'Wicklow', en: 'Wicklow', ga: 'Cill Mhantáin', lat: 52.9889, lon: -6.0127 }
  ].freeze
  # Last-resort coordinates when config, IP-geo and cache have all failed — a neutral
  # null-island, never a real place, so a misconfigured station reads as "nowhere set"
  # rather than silently borrowing someone else's location.
  DEFAULT_COORDS = { lat: 0.0, lon: 0.0, place: 'the station' }.freeze
  # OSM address keys, most-local first — the "best guess" for where we are.
  PLACE_KEYS = %w[hamlet village locality town suburb city municipality].freeze

  # A cache older than this is due a refresh. Timers refresh every 30 min where they
  # exist; the margin keeps a healthy timer from ever racing the self-heal below.
  STALE_AFTER = 35.minutes
  # After a failed self-heal attempt (offline, say), wait this long before another read
  # tries again — so an offline box isn't spawning a doomed fetch on every page load.
  RETRY_AFTER = 5.minutes

  class << self
    # Reads are SELF-HEALING: where a refresh timer exists (Pi systemd, cloud recurring
    # job) it does the work, but a dev machine has no timer, cache files get lost in
    # moves, and schedulers can die — so a read that finds the cache missing or stale
    # kicks ONE throttled background refresh. The offline-first contract still holds:
    # `current` itself never touches the network and never blocks on the refresh.
    def current(now: Time.current)
      data = read(now)
      auto_refresh(now, data[:fetched_at])
      data
    end

    def refresh(now: Time.current)
      coords = resolve_coords
      prev = current(now: now)
      forecast = fetch_forecast(coords)
      # An inland station (tides: none) never hits the tide service at all.
      tide = tide_config == :none ? nil : fetch_tide_extrema(coords, now)
      data = {
        coords:       coords,
        weather:      forecast[:weather] || prev[:weather],
        sun:          forecast[:sun] || prev[:sun],
        # Store the nearest station's predicted high/low WATERS (a few days of them) + its
        # name — `current` picks the next turning point from the list live on each read.
        tide_extrema: (tide && tide[:extrema]) || prev[:tide_extrema],
        tide_station: (tide && tide[:station]) || prev[:tide_station],
        fetched_at:   now.iso8601
      }
      write(data)
      current(now: now)
    end

    # The raw cache read (no self-heal) — everything `current` used to be.
    def read(now)
      return blank unless STORE.exist?

      data = JSON.parse(STORE.read, symbolize_names: true)
      data[:fetched_at] = safe_time(data[:fetched_at])
      # The tide is computed FRESH on every read from the cached forecast series, so it
      # always names the genuine NEXT turning point relative to now — never a value frozen
      # at fetch time that goes stale (or past) as the hours pass. Pure computation, no
      # network: the offline-first contract holds.
      data[:tide] = live_tide(data, now)
      data
    rescue JSON::ParserError, SystemCallError
      blank
    end

    # --- Pure helpers (no network; unit-tested) --------------------------------

    # A WMO code + temperature into the facts-row shape. Unknown codes degrade to
    # a thermometer rather than blowing up.
    def weather_from(temp, code)
      en, ga, emoji = WMO.fetch(code.to_i, ['—', '—', '🌡️'])
      { temp: temp.round, text: en, text_ga: ga, emoji: emoji }
    end

    # Today's sunrise/sunset (HH:MM) from Open-Meteo's daily arrays, or nil.
    def sun_from(daily)
      rise = daily && daily['sunrise']&.first
      set = daily && daily['sunset']&.first
      return nil unless rise && set

      { rise: hhmm_of(rise), set: hhmm_of(set) }
    end

    # "2026-07-03T05:12" → "05:12".
    def hhmm_of(iso)
      iso.to_s[/T(\d{2}:\d{2})/, 1]
    end

    # The next predicted turning point strictly after `now`, from a list of extrema
    # ([{ t: iso8601, type: 'high'|'low' }]) — the Marine Institute's high/low waters.
    # `station` (a { en:, ga: } hash) names the port. `offset_minutes` shifts every
    # prediction (a local spot whose tide lags/leads the port). Nil when nothing is upcoming.
    def next_tide(extrema, now, station = nil, offset_minutes: 0)
      upcoming = Array(extrema).
                 filter_map { |e| [safe_time(e[:t]), e[:type]] if e[:t] && e[:type] }.
                 map { |time, type| [time && (time + (offset_minutes * 60)), type] }.
                 select { |time, _| time && time > now }.
                 min_by(&:first)
      return nil unless upcoming

      tide(upcoming[1].to_sym, upcoming[0], station)
    end

    # The next tide derived live from the cached predictions (no network) — recomputed on
    # every read so it always names the genuine upcoming water, honouring the station.yml
    # `tides:` setting (none | default | offset + a local name) at READ time, so a config
    # change shows without a refetch. Falls back to any legacy single-tide value, else nil.
    def live_tide(data, now = Time.current)
      config = tide_config
      return nil if config == :none

      extrema = data[:tide_extrema]
      return data[:tide] unless extrema.is_a?(Array) && extrema.any?

      if config.is_a?(Hash)
        next_tide(extrema, now, config[:name] || data[:tide_station], offset_minutes: config[:offset_minutes])
      else
        next_tide(extrema, now, data[:tide_station])
      end
    end

    # station.yml `tides:` → :none (inland, no tide anywhere), :default (nearest Marine
    # Institute station, as shipped), or { offset_minutes:, name: {en:, ga:} } — the local
    # spot's lag/lead on the nearest station and what to call it.
    #   tides: none            |  tides: default (or unset)
    #   tides:
    #     offset: 25m          # or -15m — minutes relative to the nearest station
    #     i18n: { en: Back beach, ga: Trá beag }
    def tide_config
      raw = Station.setting('tides')
      case raw
      when Hash
        i18n = raw['i18n'] || {}
        { offset_minutes: parse_offset_minutes(raw['offset']),
          name:           i18n['en'].presence && { en: i18n['en'], ga: i18n['ga'].presence || i18n['en'] } }
      when /\A:?none\z/ then :none # tolerate YAML `none` and `:none` alike
      else :default
      end
    end

    # The nearest tidal port to a position — flat-earth distance with longitude scaled
    # for latitude (accurate enough at Ireland's scale). Used to name the tide's station.
    def nearest_tide_station(lat, lon)
      scale = Math.cos(lat * Math::PI / 180)
      TIDE_STATIONS.min_by { |s| ((s[:lat] - lat)**2) + (((s[:lon] - lon) * scale)**2) }
    end

    # Best-guess place label from an OSM reverse-geocode address hash — the most
    # local named thing, then the county (e.g. "Tullycross, County Galway").
    def place_from(address)
      return nil unless address

      local = PLACE_KEYS.filter_map { |k| address[k] }.first
      [local, address['county']].compact.uniq.join(', ').presence
    end

    private

    # "25m" / "-15m" / "25" / 25 → minutes as an Integer (0 when unset/unparseable).
    def parse_offset_minutes(raw)
      raw.to_s[/-?\d+/].to_i
    end

    # Kick one background refresh when the cache is missing or stale. Throttled: never
    # while one is in flight, never within RETRY_AFTER of the last attempt, and never in
    # tests (specs must not dial out). Failures just leave the last-good cache — the next
    # eligible read retries.
    def auto_refresh(now, fetched_at)
      return if Rails.env.test?
      return if fetched_at && fetched_at > now - STALE_AFTER
      return if @refreshing
      return if @last_attempt_at && @last_attempt_at > now - RETRY_AFTER

      @refreshing = true
      @last_attempt_at = now
      Thread.new do
        refresh
      rescue StandardError => e
        Rails.logger.warn("Almanac: self-heal refresh failed (#{e.class}: #{e.message})")
      ensure
        @refreshing = false
      end
    end

    def blank
      { coords: nil, weather: nil, sun: nil, tide: nil, tide_extrema: nil, tide_station: nil, fetched_at: nil }
    end

    def tide(kind, time, station = nil)
      hhmm = time.strftime('%H:%M')
      en, ga = TIDE_LABELS.fetch(kind)
      label = "#{en} #{hhmm}"
      label_ga = "#{ga} #{hhmm}"
      if station
        label = "#{label} · #{station[:en]}"
        label_ga = "#{label_ga} · #{station[:ga] || station[:en]}"
      end
      { type: kind.to_s, time: hhmm, station: station&.fetch(:en, nil), label: label, label_ga: label_ga }
    end

    # Where are we? Configured coordinates win (the station is a fixed spot);
    # otherwise the device auto-detects via IP geolocation, then the last cache,
    # then a neutral default. The place name is a best guess: an explicit BIRD_PLACE if set,
    # else a reverse-geocode of the coordinates, else whatever IP geo named.
    def resolve_coords
      base = configured_latlon || fetch_geo || current[:coords] || DEFAULT_COORDS
      { lat: base[:lat], lon: base[:lon], place: resolve_place(base) }
    end

    # A bilingual place label {en:, ga:}. An explicit BIRD_PLACE wins (same in
    # both); otherwise reverse-geocode once per language, so a bilingual townland
    # reads in either tongue as the chrome toggle asks.
    def resolve_place(base)
      return { en: ENV['BIRD_PLACE'], ga: ENV['BIRD_PLACE'] } if ENV['BIRD_PLACE'].present?

      en = reverse_place(base[:lat], base[:lon], 'en')
      ga = reverse_place(base[:lat], base[:lon], 'ga')
      fallback = en || ga || base_place(base)
      { en: en || fallback, ga: ga || fallback }
    end

    def base_place(base)
      place = base[:place]
      place.is_a?(Hash) ? (place[:en] || place[:ga]) : place
    end

    def configured_latlon
      return nil unless ENV['BIRD_LAT'].present? && ENV['BIRD_LON'].present?

      { lat: ENV['BIRD_LAT'].to_f, lon: ENV['BIRD_LON'].to_f }
    end

    def fetch_geo
      json = get_json('http://ip-api.com/json/?fields=status,lat,lon,city')
      return nil unless json && json['status'] == 'success'

      { lat: json['lat'].to_f, lon: json['lon'].to_f, place: json['city'] }
    end

    # Reverse-geocode to a locality via OSM Nominatim in one language (no key; a
    # valid User-Agent + our 30-min cadence stay well within its usage policy).
    def reverse_place(lat, lon, lang)
      json = get_json("https://nominatim.openstreetmap.org/reverse?lat=#{lat}&lon=#{lon}&format=jsonv2&zoom=13&addressdetails=1&accept-language=#{lang}")
      place_from(json && json['address'])
    end

    # One Open-Meteo call for both the current conditions and today's sun times.
    def fetch_forecast(coords)
      json = get_json("https://api.open-meteo.com/v1/forecast?latitude=#{coords[:lat]}&longitude=#{coords[:lon]}&current=temperature_2m,weather_code&daily=sunrise,sunset&timezone=auto")
      return {} unless json

      cur = json['current']
      if cur && cur['temperature_2m'] && cur['weather_code']
        weather = weather_from(cur['temperature_2m'],
                               cur['weather_code'])
      end
      { weather: weather, sun: sun_from(json['daily']) }.compact
    end

    # The Marine Institute's predicted high/low waters for the nearest station, from a few
    # hours before `now` out three days — enough that `live_tide` always finds the next
    # turning point between refreshes. ERDDAP times are UTC; safe_time parses them and the
    # label renders in the app zone (Europe/Dublin). Returns
    # { extrema: [{ t:, type: }], station: { en:, ga: } } or nil on a failed fetch.
    def fetch_tide_extrema(coords, now)
      station = nearest_tide_station(coords[:lat], coords[:lon])
      return nil unless station

      from = (now - 6.hours).utc.iso8601
      to = (now + 3.days).utc.iso8601
      url = "#{ERDDAP_BASE}?time,tide_time_category&stationID=%22#{station[:id]}%22" \
            "&time%3E=#{from}&time%3C=#{to}&orderBy(%22time%22)"
      rows = get_json(url, timeout: ERDDAP_TIMEOUT)&.dig('table', 'rows')
      return nil unless rows&.any?

      extrema = rows.filter_map { |time, category| tide_extremum(time, category) }
      extrema.any? ? { extrema: extrema, station: station.slice(:en, :ga) } : nil
    end

    # One ERDDAP row → { t:, type: }, or nil for an unrecognised category.
    def tide_extremum(time, category)
      kind = { 'high' => 'high', 'low' => 'low' }[category.to_s.downcase]
      { t: time, type: kind } if kind && time
    end

    def get_json(url, timeout: HTTP_TIMEOUT)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                            open_timeout: timeout, read_timeout: timeout) do |http|
        http.get(uri.request_uri, 'User-Agent' => Station.user_agent)
      end
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    rescue StandardError
      nil
    end

    def safe_time(value)
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def write(data)
      STORE.dirname.mkpath # storage/ is runtime state — create it rather than ENOENT
      tmp = STORE.sub_ext('.tmp')
      tmp.write(JSON.pretty_generate(data))
      tmp.rename(STORE.to_s) # atomic replace so a reader never sees a half-written file
    end
  end
end
