namespace :ealta do
  desc 'Regenerate the home page "today" summary (Nova Lite via Bedrock) into storage/today_summary.json'
  task summary_refresh: :environment do
    result = TodaySummary.refresh
    puts "summary refreshed (#{result[:source]}):"
    result[:bullets].each do |lang, bullets|
      puts "  [#{lang}]"
      bullets.each { |bullet| puts "    #{bullet}" }
    end

    # Freeze yesterday's Journal entry if it isn't yet. The Pi has no daily Solid Queue sweep,
    # so this timer is its pre-warm; after the first build it's a cheap cache read. Best-effort
    # — build-on-view is the backstop everywhere.
    begin
      entry = JournalEntry.for(Date.yesterday)
      puts "journal #{entry&.date} frozen (#{entry&.source || 'n/a'})"
    rescue StandardError => e
      warn "journal freeze skipped (#{e.class}: #{e.message})"
    end
  end
end
