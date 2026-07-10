module Api
  # GET /api/stats?h= — the Stats tab (bar list + by-period + first detections).
  class StatsController < BaseController
    def show
      render json: {
        window:        current_window,
        summary_cards: summary_cards,
        top_species:   Detection.tally_within(current_window).first(12).map { |t| tally_json(t) },
        by_period:     periods_json,
        first_seen:    Detection.first_detections.map { |e| life_json(e) }
      }
    end

    private

    # The continuity numbers — the accumulated record, not "today". "Days
    # listening" is the point: an ongoing chronicle for a device that sits on a
    # wall for years (day 1 is the first day anything was heard).
    def summary_cards
      age = DailyFacts.station_age_days
      {
        species_logged:      Detection.life_list.size,
        detections_all_time: Detection.count,
        days_listening:      Detection.exists? ? age + 1 : 0
      }
    end
  end
end
