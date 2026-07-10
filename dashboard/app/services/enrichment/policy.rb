module Enrichment
  # How often a species' facts & folklore are re-sourced — a backoff keyed on how
  # interesting the bird is right now, using the importance DailyFacts already computes.
  #
  # The point: facts don't change day to day, so there is no reason to keep paying
  # Claude to re-derive the same house-sparrow notes. But a bird that is *notable now*
  # earns fresh lookups: when the cuckoo arrives in April it reads as rare_local for its
  # first days back (heard on ≤5 of the last 200 days), so it stays notable across that
  # window → new facts & folklore every day for the arrival — then it settles into a
  # common resident and the lookups stop. A vagrant tanager is notable the whole time it
  # lingers; a house sparrow is never notable, so it's sourced once and then left alone.
  module Policy
    NOTABLE      = DailyFacts::NOTABLE_IMPORTANCE # 60
    HOT_DAYS     = 1    # notable now (new / seasonal-return / rare): refresh daily
    WARM_DAYS    = 30   # mildly unusual (e.g. an odd volume): about monthly
    ROUTINE_DAYS = 180  # common residents: sourced once, twice a year at most

    module_function

    # Days before a bundle for a bird of this importance is stale and worth re-sourcing.
    def refresh_interval_days(importance)
      if importance >= NOTABLE then HOT_DAYS
      elsif importance >= 30 then WARM_DAYS
      else ROUTINE_DAYS
      end
    end

    # Should we (re)source this species as of `as_of`? Yes if we hold nothing usable,
    # or the current bundle is older than the backoff its importance earns.
    def due?(sci_name, importance, as_of: Date.current)
      current = EnrichmentBundle.current(sci_name)
      return true if current.nil? || current.block_objects.empty?

      (as_of - current.date).to_i >= refresh_interval_days(importance)
    end
  end
end
