module Api
  # GET /api/overview?h= — everything the Birds tab renders.
  class OverviewController < BaseController
    # How long a rendered overview may be reused. This response is the gate on the whole Live
    # view — the SPA cannot draw a single bird until it lands — so every visitor was paying to
    # rebuild the same anonymous payload. Rails' ETag default (`max-age=0, private,
    # must-revalidate`) meant neither the browser nor CloudFront could keep it.
    #
    # 30s against the SPA's own 60s refetchInterval: nobody sees anything staler than the poll
    # they already accept, and concurrent readers collapse onto one origin render instead of
    # one each. stale-while-revalidate then lets the refresh happen behind an instant serve,
    # so the window boundary isn't a latency spike for whoever lands on it.
    #
    # SAFE TO SHARE, and checked rather than assumed: the action touches no session, cookie or
    # current_user; the response sets no cookie; and the body is byte-identical with and
    # without a session cookie. Favourites are deliberately computed client-side (see
    # LiveTab) precisely so this stays one payload for everyone. Anything that ever makes this
    # per-reader must take this header off first — the CDN default is CachingDisabled for the
    # good reason recorded in cdn.tf, and this is a narrow, deliberate exception to it.
    CACHE_FOR = 30.seconds

    def show
      expires_in CACHE_FOR, public: true, stale_while_revalidate: 5.minutes
      tally = Detection.tally_within(current_window)
      render json: {
        window:  current_window,
        collage: collage_json(CollagePresenter.new(tally)),
        numbers: {
          species_today:       Detection.tally_for.size,
          detections_today:    Detection.today.count,
          detections_all_time: Detection.count
        },
        # The window's headline figures — detections, species and listening duration — for the
        # stats line above Recently heard. Detections/species are the selected window's (not the
        # calendar day's); duration is the time the mic was actually up across it (gaps removed),
        # nil for the "all time" span where a lifetime figure isn't a listening duration.
        stats:   {
          detections:       tally.sum(&:count),
          species:          tally.size,
          duration_seconds: TodayCard.listening_seconds(window_hours: current_window)
        },
        # Most common in the window (the tally is already loudest-first).
        top:     tally.first(6).map { |t| tally_json(t) },
        # Most recently heard, freshest first — Live's present-tense running log (same sort
        # the kiosk's "recent" uses). The collage shows *which* birds; this shows *when*.
        # Rankings, life list and first-seen are the Stats page's job, not duplicated here.
        recent:  tally.sort_by { |t| t.last_time.to_s }.last(12).reverse.map { |t| tally_json(t) },
        periods: periods_json,
        almanac: almanac_json,
        today:   today_json,
        notable: notable_json,
        status:  AdminHealth.status
      }
    end
  end
end
