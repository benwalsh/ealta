module Api
  # GET /api/species/:sci — the species-detail modal blob (bilingual names,
  # counts, conservation, illustrations, Wikipedia prose, song, recent hearings).
  class SpeciesController < BaseController
    def show
      sci = params[:sci]
      name = BirdName.lookup(sci)
      scope = Detection.where(Sci_Name: sci)
      recent = scope.order(Arel.sql("#{Detection.when_sql} DESC")).limit(24)
      render json: {
        sci: sci, en: name.en, ga: name.ga,
        all_time: scope.count,
        today: scope.merge(Detection.today).count,
        first_seen: parse_time(scope.minimum(Arel.sql(Detection.when_sql)))&.iso8601,
        conservation: { status: Conservation.status(sci), name: Conservation.name(sci), note: Conservation.note(sci) },
        illustrations: helpers.bird_illustrations(sci).map { |label, url| { label: label, url: url } },
        description: SpeciesInfo.english_for(sci, name.en),
        description_ga: SpeciesInfo.irish_for(sci, name.ga),
        song: SongSample.url_for(sci),
        recent: recent.map { |d| { at: d.heard_at&.iso8601, confidence: d.confidence.to_f } },
        # The latest fact + folklore, if a bundle has been sourced for this bird. Nil
        # otherwise — the card then offers a signed-in viewer an on-demand look-up
        # (EnrichmentController), so facts stay reachable regardless of the daily backoff.
        enrichment: EnrichmentBundle.current(sci)&.to_display
      }
    end

    private

    def parse_time(string)
      Time.zone.parse(string) if string.present?
    rescue ArgumentError
      nil
    end
  end
end
