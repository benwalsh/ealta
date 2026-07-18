namespace :ealta do
  desc 'Warm the species-detail cache so the modal never opens cold (SCI=\'Genus species\' for one; FORCE=1 to refetch)'
  task warm_species: :environment do
    # Why this exists: /api/species/:sci builds the modal by calling SpeciesInfo.english_for,
    # .irish_for and SongSample.url_for inline. Cold, that is a Wikipedia fetch, an LLM summary,
    # an LLM translation (which WAITS on the summary — it translates it) and a Commons audio
    # search, in series: measured at ~11s on the first click, ~0.1s every click after. The work
    # is identical whenever it happens, so it should happen before anyone is waiting on it.
    #
    # The station hears a small, near-fixed cast — warming the life list once means essentially
    # every click lands warm, and a genuinely new bird is the only one that can ever pay the
    # cost. Idempotent: species already cached are skipped unless FORCE=1.
    only = ENV['SCI'].presence
    force = ENV['FORCE'].present?

    scis = (only ? [only] : Detection.life_list.map(&:sci_name)).compact.uniq
    abort 'no species to warm (empty life list)' if scis.empty?

    puts "warming #{scis.size} species#{' (forced)' if force}   bedrock disabled?: #{Bedrock.disabled?}"
    warmed = skipped = failed = 0

    scis.each do |sci|
      # "Warm" is SpeciesInfo.content_ready? — the same test the ingest hook enqueues on and
      # the job re-checks, so this task and the live path can never disagree about what is done.
      if !force && SpeciesInfo.content_ready?(sci)
        skipped += 1
        next
      end

      # FORCE has to CLEAR the stored text, not merely skip the check: english_for/irish_for
      # return whatever is cached the moment it is present, so without this a forced run
      # re-read the same rows and changed nothing. That is how stale lead-paragraph
      # descriptions, cached while the model was unavailable, survived every attempt to
      # refresh them.
      if force
        SpeciesInfo.find_by(sci_name: sci)&.update(description: nil, description_ga: nil,
                                                   fetched_at: nil, fetched_ga_at: nil)
      end

      name = BirdName.lookup(sci)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        SpeciesInfo.english_for(sci, name.en)
        SpeciesInfo.irish_for(sci, name.ga)
        SongSample.url_for(sci)
        warmed += 1
        puts format('  %-34s %5.1fs', sci, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      rescue StandardError => e
        # One bird's bad article must not abandon the rest of the list.
        failed += 1
        puts "  #{sci.ljust(34)} FAILED (#{e.class}: #{e.message.to_s[0, 60]})"
      end
    end

    puts "done: #{warmed} warmed, #{skipped} already warm, #{failed} failed"
  end
end
