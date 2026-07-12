module ApplicationHelper
  # A bilingual inline string for server-rendered pages: both languages sit in the DOM and
  # the [data-lang] CSS shows the active one, so the language toggle flips them live (the
  # same mechanism the SPA uses). Irish UI wording here is a first pass — worth a native check.
  def bi(en, ga)
    safe_join([tag.span(en, class: 'lang-en'), tag.span(ga, class: 'lang-ga')])
  end

  # A single-language string for attribute contexts (a prompt, a value) where two spans
  # can't go; picks server-side, so it updates on the next load rather than live.
  def t2(en, ga)
    ui_lang == 'ga' ? ga : en
  end

  # Compact relative time like the parent's panel: "now", "8h ago", "36d ago".
  def heard_ago(time)
    return '—' unless time

    secs = Time.current - time
    case secs
    when 0...60 then 'now'
    when 60...3600 then "#{(secs / 60).floor}m ago"
    when 3600...86_400 then "#{(secs / 3600).floor}h ago"
    else "#{(secs / 86_400).floor}d ago"
    end
  end

  # Station coordinates in a compact "53.6°N 9.9°W" form.
  def format_coords(lat, lon)
    ns = lat.negative? ? 'S' : 'N'
    ew = lon.negative? ? 'W' : 'E'
    format('%<lat>.1f°%<ns>s %<lon>.1f°%<ew>s', lat: lat.abs, ns: ns, lon: lon.abs, ew: ew)
  end

  # URL for a species' illustration, or nil if the station ships none. The art lives in
  # the station profile and is served by StationAssetsController; the /birds/ URL shape
  # is unchanged, only the source of the bytes.
  # Availability comes from masks.json (BirdMask), which lists every bird that HAS art and ships
  # with the profile — NOT from a PNG on disk, since the art may be CDN-served and absent from
  # the cloud image, with /birds/<slug>.png redirecting there.
  def bird_illustration(sci)
    slug = sci.downcase.tr(' ', '-')
    BirdMask.for(slug) ? "/birds/#{slug}.png?v=#{illustration_version}" : nil
  end

  # Both illustration poses for the modal — perched and (when we have it) in flight — as
  # [label, url] pairs, skipping any the station doesn't ship.
  def bird_illustrations(sci)
    slug = sci.downcase.tr(' ', '-')
    { 'perched' => slug, 'in flight' => "#{slug}-2" }.filter_map do |label, name|
      [label, "/birds/#{name}.png?v=#{illustration_version}"] if BirdMask.for(name)
    end
  end

  private

  # One cache-busting stamp for illustration URLs: masks.json's mtime, rebuilt whenever the art
  # is regenerated. Works when the PNGs are CDN-served rather than on local disk.
  def illustration_version
    @illustration_version ||= StationProfile.path('illustrations/masks.json')&.mtime.to_i
  end
end
