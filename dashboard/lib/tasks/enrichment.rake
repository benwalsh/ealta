namespace :ealta do
  desc "Stage 1: source enrichment bundles for a date (DATE=YYYY-MM-DD, SCI='Genus species' to force one)"
  task enrich: :environment do
    date = ENV['DATE'].present? ? Date.parse(ENV['DATE']) : Date.current
    only = ENV['SCI'].present? ? { sci_name: ENV['SCI'] } : nil

    puts "Stage 1 — sourcing enrichment for #{date}#{" (forced: #{only[:sci_name]})" if only}"
    puts "  model: #{Bedrock.enrich_model_id}   bedrock disabled?: #{Bedrock.disabled?}"
    bundles = Enrichment::Builder.run(date: date, only: only)
    if bundles.empty?
      puts '  no bundles produced (no notable species, or the model/creds are unavailable).'
    else
      bundles.each { |b| print_bundle(b) }
    end
  end

  desc 'Run the full email-construction flow for one reader and render a preview (USER=id DATE=YYYY-MM-DD)'
  task email_flow: :environment do
    user = ENV['USER'].present? ? User.find(ENV['USER']) : User.first
    date = ENV['DATE'].present? ? Date.parse(ENV['DATE']) : Date.yesterday
    abort 'no user found (pass USER=<id>)' unless user

    rule "1. TODAY'S DATA — #{date}"
    facts = DailyFacts.for(date: date)
    digest = DigestFacts.for(user: user, date: date)
    puts "  #{facts[:species_today]} species, #{facts[:detections_today]} detections."
    notable = EnrichmentGate.species_for(facts)
    puts "  notable birds (clear the enrichment bar): #{notable.pluck(:common_name).presence&.join(', ') || 'none'}"

    rule '2. STAGE 1 (Claude) — the interesting bits, sourced'
    puts "  model: #{Bedrock.enrich_model_id}   bedrock disabled?: #{Bedrock.disabled?}"
    # Source the day's notable birds AND the reader's own followed birds heard today,
    # each only when the importance-keyed backoff says it's DUE — so a routine follow
    # (a house sparrow) is sourced once and then left alone, while a rare or newly-
    # arrived bird gets fresh facts every day for its window.
    importance = facts.fetch(:items, []).to_h { |i| [i[:sci_name], i[:importance]] }
    wanted = (notable.pluck(:sci_name) + digest.follows.pluck(:sci)).uniq
    wanted.each do |sci|
      unless Enrichment::Policy.due?(sci, importance[sci].to_i, as_of: date)
        puts "  #{sci}: current (backoff) — reusing"
        next
      end
      puts "  sourcing #{sci}…"
      Enrichment::Builder.build_one(date: date, sci_name: sci)
    end
    bundles = EnrichmentBundle.for_date(date).select { |b| b.block_objects.any? }
    if bundles.empty?
      puts '  no enrichment available — the email will use the plain summary.'
      if (err = Enrichment::Builder.last_error)
        puts "  reason: #{err.class} — #{err.message.to_s.lines.first&.strip}"
        if err.message.to_s.match?(/use case|not been submitted|AccessDenied|ResourceNotFound/i)
          puts '  → the Bedrock Anthropic "use case details" form is not submitted for this'
          puts '    account. Fill it in the AWS console (Bedrock → Model access), wait ~15 min,'
          puts '    then re-run. Claude is the sourcing model; do not swap in another.'
        end
      end
    else
      bundles.each { |b| print_bundle(b) }
    end

    rule "3. THE READER — #{user.email}"
    puts "  follows heard: #{digest.follows.map { |f| "#{f[:en]} ×#{f[:count]}" }.presence&.join(', ') || 'none'}"
    puts "  standing-rule arrivals: #{digest.alerts.pluck(:en).presence&.join(', ') || 'none'}"
    puts "  daily letter: #{digest.roundup ? 'yes' : 'no'}"

    rule '4. STAGE 2 (Nova) — the note, assembled for this reader'
    note = Enrichment::Assembler.for(user: user, date: date)
    source = 'enrichment-assembled (Nova over the cited blocks)'
    if note.nil?
      note = DigestSummary.for(digest)
      source = note ? 'plain summary (Nova, no enrichment used)' : 'mechanical list (no model)'
    end
    puts "  source: #{source}"
    Array(note).each { |para| puts "  #{para}" }

    rule '5. RENDERED EMAIL'
    html = Notifier.send(:digest_html, digest, date, note)
    text = Notifier.send(:digest_text, digest, date, note)
    out = Rails.root.join('tmp/digest_preview.html')
    File.write(out, html)
    puts text.lines.map { |l| "  #{l}" }.join
    puts "\n  HTML preview written to #{out}"
  end

  # A self-contained "try it" for when Claude's sourcing is still gated by the Bedrock
  # Anthropic use-case form. It STANDS IN a few real, cited Claude-quality bundles, then
  # runs the REAL Nova assembler + render for a reader who follows the interesting birds,
  # and shows the importance backoff deciding when to re-source. Everything runs inside a
  # transaction that is rolled back — no temp user, no bundle, nothing persists.
  # Needs Nova creds for the live stitch:  AWS_PROFILE=ealta bin/rake ealta:email_demo
  task email_demo: :environment do
    date = ENV['DATE'].present? ? Date.parse(ENV['DATE']) : Date.new(2026, 7, 4)
    ENV['BIRD_PLACE'] ||= 'Somewhere' # a placeholder so the demo has a place to name
    place = Station.region

    # rubocop:disable Layout/LineLength -- prose data reads better unwrapped
    demo_bundles = {
      'Apus apus'           => ['Common Swift', 'Gabhlán gaoithe', [
        ['fact', false,
         'The swift spends almost its whole life on the wing — feeding, mating and even sleeping in flight — and a young bird may stay airborne for its first two or three years.', 'en.wikipedia.org'],
        ['regional_note', false,
         'In Ireland it is a summer visitor only, arriving in May and gone by August, its screaming parties racing low over coastal villages.', 'birdwatchireland.ie'],
        ['folklore', true,
         'Its dark, scythe-winged shape and shrill call earned it old country names like “devil bird”.', 'en.wikipedia.org']
      ]],
      'Carduelis carduelis' => ['European Goldfinch', 'Lasair choille', [
        ['fact', false,
         'Its slender, pointed bill lets it pull seeds from teasel and thistle heads that heavier-billed finches cannot reach.', 'en.wikipedia.org'],
        ['regional_note', false,
         'A common Irish resident whose Irish name, Lasair choille, means “flame of the woods”, for the crimson face and gold wing-flash.', 'birdwatchireland.ie'],
        ['folklore', true,
         'A flock of goldfinches is called a “charm”; in medieval painting the bird stood for the soul.', 'en.wikipedia.org']
      ]]
    }
    # rubocop:enable Layout/LineLength

    ActiveRecord::Base.transaction do
      demo_bundles.each do |sci, (common, irish, rows)|
        EnrichmentBundle.create!(sci_name: sci, date: date, common_name: common, irish_name: irish,
                                 blocks: rows.map do |type, gated, text, host|
                                   { type: type, id: "#{sci.parameterize}-#{type}", text: text, gated: gated,
                                     sources: [{ host: host, url: "https://#{host}/#{sci.parameterize}" }] }
                                 end)
      end

      rule '1. BACKOFF — how often each bird is re-sourced (importance-keyed)'
      [['Cuculus canorus', 'cuckoo, newly back', 80],
       ['Passer domesticus', 'house sparrow, routine', 5]].each do |sci, label, imp|
        every = Enrichment::Policy.refresh_interval_days(imp)
        cur = EnrichmentBundle.current(sci)
        state = cur ? "last sourced #{(date - cur.date).to_i}d ago" : 'never sourced'
        puts "  #{label}: importance #{imp} → re-source every #{every} day#{'s' unless every == 1} (#{state})"
      end

      reader = User.create!(provider: 'demo', uid: "demo-#{date}", email: 'you@example.com', name: 'You')
      demo_bundles.each_key do |sci|
        reader.subscriptions.create!(alert_type: 'species', sci_name: sci, cadence: 'digest')
      end
      reader.subscriptions.create!(alert_type: 'roundup', cadence: 'digest')

      facts = DigestFacts.for(user: reader, date: date)
      follows = facts.follows.map { |f| "#{f[:en]} ×#{f[:count]}" }.join(', ').presence
      rule "2. THE READER at #{place} — follows #{follows || '(none heard — try DATE=2026-07-04)'}"

      rule '3. NOVA stitches the saved pieces into the note'
      note = Enrichment::Assembler.for(user: reader, date: date)
      if note
        puts '  source: Nova over the cited blocks'
      else
        note = DigestSummary.for(facts)
        fallback = note ? 'plain summary (no enrichment)' : 'mechanical list — set AWS_PROFILE=ealta'
        puts "  source: #{fallback}"
      end
      Array(note).each { |p| puts "  #{p}" }

      out = Rails.root.join('tmp/email_demo.html')
      File.write(out, Notifier.send(:digest_html, facts, date, note))
      puts "\n  HTML preview written to #{out}  (open it: open #{out})"

      raise ActiveRecord::Rollback
    end
    puts "\n  (nothing was saved — the demo user and bundles were rolled back)"
  end
end

def print_bundle(bundle)
  puts "  • #{bundle.common_name} (#{bundle.sci_name})"
  bundle.block_objects.each do |block|
    hosts = block.sources.map { |s| s[:host] }.join(', ')
    puts "      [#{block.type}#{', gated' if block.gated?}] #{block.text}"
    puts "        ← #{hosts}" if hosts.present?
  end
end

def rule(title)
  puts "\n#{'─' * 4} #{title} #{'─' * [0, 64 - title.length].max}"
end
