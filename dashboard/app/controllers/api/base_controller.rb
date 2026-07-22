module Api
  # Shared JSON serialization for the SPA's data endpoints. All read-only GETs off
  # the existing model/presenter methods — the same numbers the server-rendered
  # views used, now shaped for React (and, later, a public API host).
  class BaseController < ApplicationController
    private

    # A SpeciesTally → the windowed-count shape (bilingual name + last heard).
    def tally_json(tally)
      {
        sci: tally.sci_name, en: tally.name.en, ga: tally.name.ga,
        count: tally.count, last_time: tally.last_time, confidence: tally.confidence
      }
    end

    # A LifeEntry → life-list shape (totals + conservation status).
    def life_json(entry)
      {
        sci: entry.sci_name, en: entry.name.en, ga: entry.name.ga, count: entry.count,
        first_seen: entry.first_seen, last_seen: entry.last_seen,
        conservation: Conservation.status(entry.sci_name),
        image: helpers.bird_illustration(entry.sci_name)
      }
    end

    def collage_json(collage)
      {
        width: collage.width, height: collage.height,
        species_count: collage.species_count, nodes: collage.nodes.map(&:to_h)
      }
    end

    def periods_json
      Detection.by_period.map { |label, count| { label: label, count: count } }
    end

    # The home page's "TODAY" card, shaped entirely in Ruby (bullets, sparkline
    # paths, anchors, footer) so the view only iterates and prints. See TodayCard.
    def today_json
      warm_today_summary
      TodayCard.build(window_hours: current_window)
    end

    # Keep the daily summary warm — by NOTICING it has gone stale, never by regenerating it
    # here. The note is re-stitched every 30 minutes, and this used to do that inline: the
    # first visitor after the window paid for DailyFacts plus a Bedrock call inside their page
    # load, while every collage image queued behind the response. Measured at 1,014ms on the
    # unlucky load and ~140ms on the rest. The regeneration is identical whoever triggers it,
    # so it belongs in a job (see WarmTodaySummaryJob).
    #
    # The reader gets the previously cached note, which is what they'd have got anyway for the
    # 30 minutes before this — just now for a few seconds longer, rather than one reader in
    # thirty minutes waiting on a model.
    def warm_today_summary
      return unless TodaySummary.stale?(max_age: 30.minutes)

      # One job per stale window, not one per visitor. `unless_exist` makes this an atomic
      # claim, so a burst of concurrent readers (exactly what a stale window ends with)
      # enqueues once rather than each queueing their own duplicate narration. The 5-minute
      # lease is a backstop: if the job dies before clearing staleness, the next load re-tries
      # rather than the note being stuck until the day rolls over.
      return unless Rails.cache.write('today_summary/warming', true, expires_in: 5.minutes, unless_exist: true)

      WarmTodaySummaryJob.perform_later
    rescue StandardError => e
      # Enqueueing must never break a page. Without a queue we simply serve the cached note.
      Rails.logger.warn("today_json: summary warm skipped (#{e.class}: #{e.message})")
    end

    # New & notable, grouped by kind: the newsworthy Events (rarity / first-ever /
    # seasonal) for the given window, each a distinct bird — the same fire-once Events
    # the email alerts fire on, so panel, site and email agree on "news". A fixed
    # three-key shape (empty lists where there's nothing), freshest first within each.
    # Live passes the default 2-day window; the Journal passes a single completed date.
    def notable_json(as_of: Date.current, days: 2)
      grouped = Event.breaking(on: as_of, days: days).group_by(&:event_type)
      Event::NEWS_TYPES.index_with do |type|
        Array(grouped[type]).map { |e| notable_item(e.sci_name) }.uniq { |i| i[:sci] }
      end
    end

    def notable_item(sci)
      name = BirdName.lookup(sci)
      { sci: sci, en: name.en, ga: name.ga }
    end

    def moon_json
      moon = MoonPhase.for
      { name: moon.name, name_ga: moon.name_ga, illumination: moon.illumination, emoji: moon.emoji }
    end

    # Weather + tide + coordinates (from the cached almanac) + the moon, in one
    # blob for the facts row. Coords fall back to a config default; place is bilingual.
    def almanac_json
      data = Almanac.current
      coords = data[:coords] || {}
      place = coords[:place]
      place = { en: place, ga: place } if place.is_a?(String)
      place ||= {}
      lat = (coords[:lat] || ENV.fetch('BIRD_LAT', 0.0)).to_f
      lon = (coords[:lon] || ENV.fetch('BIRD_LON', 0.0)).to_f
      {
        weather: data[:weather], tide: data[:tide], sun: data[:sun], moon: moon_json,
        coords: { lat: lat, lon: lon, place_en: place[:en], place_ga: place[:ga] || place[:en],
                  label: helpers.format_coords(lat, lon) }
      }
    end
  end
end
