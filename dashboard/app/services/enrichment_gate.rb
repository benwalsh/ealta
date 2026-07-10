# Stage 0 of the daily enrichment pipeline: which of today's birds deserve a (costly,
# polite) enrichment lookup? Pure Ruby — no network, no model. It hangs off the
# importance DailyFacts already computes; it never invents a parallel notion of
# "notable". On a typical day this returns zero to a few species, and that emptiness
# is the politeness budget working as designed.
class EnrichmentGate
  class << self
    # Species at or above the notable bar (all_time_first / year_first / rare_local).
    # routine and unusual_volume alone never clear it, so common residents never
    # trigger a lookup. The watchlist is intentionally ignored here: it only affects
    # ASSEMBLY (which bird a user's email leads with) and must never lower the
    # sourcing/folklore bar — one person's follow can't spend the system's politeness
    # budget. It's in the signature to document that decision.
    def species_for(facts, watchlist: []) # rubocop:disable Lint/UnusedMethodArgument
      facts.fetch(:items, []).
        select { |item| item[:importance].to_i >= DailyFacts::NOTABLE_IMPORTANCE }.
        map { |item| item.slice(:sci_name, :common_name, :irish_name) }
    end
  end
end
