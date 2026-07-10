namespace :ealta do
  desc 'Verify the Python<->Rails<->datastore seams and Irish/UTF-8 locale (bring-up check)'
  task doctor: :environment do
    ok = true
    check = lambda do |label, cond, detail = nil|
      ok &&= cond
      puts "  [#{cond ? 'ok' : 'FAIL'}] #{label}#{" — #{detail}" if detail}"
    end

    conn = ActiveRecord::Base.connection
    puts "DATASTORE (#{ActiveRecord::Base.connection_db_config.database})"
    check.call('connects', conn.select_value('SELECT 1').to_i == 1)
    check.call('detections table (listener writes it)', conn.table_exists?('detections'))
    check.call('species_infos table (web app owns it)', conn.table_exists?('species_infos'))

    # The exact columns birdnet/listen.py INSERTs — the Python<->datastore seam.
    if conn.table_exists?('detections')
      cols = conn.columns('detections').map(&:name)
      needed = %w[Date Time Sci_Name Com_Name Confidence Lat Lon Week File_Name]
      missing = needed - cols
      check.call('listener write-columns present', missing.empty?, missing.any? ? "missing #{missing.join(', ')}" : nil)
    end

    if conn.adapter_name.match?(/sqlite/i)
      mode = conn.execute('PRAGMA journal_mode').first&.values&.first.to_s
      check.call('WAL mode (concurrent listener + web)', mode.downcase == 'wal', "journal_mode=#{mode}")
    else
      check.call('adapter (cloud mirror)', true, conn.adapter_name)
    end

    # The one cross-database seam (Detection.when_sql) actually executes.
    when_ok = begin
      Detection.tally_within(1_000_000)
      true
    rescue StandardError
      false
    end
    check.call('chronological query (when_sql) runs', when_ok, Detection.when_sql)

    puts "\nNAMES / UTF-8 (the locale seam)"
    robin = BirdName.lookup('Erithacus rubecula')
    lang = BirdName.secondary_language
    check.call('English labels load', robin.en == 'European Robin', "robin -> #{robin.en.inspect}")
    if lang
      chough = BirdName.lookup('Pyrrhocorax pyrrhocorax')
      check.call("second-language labels load (#{lang})", robin.ga.present?, "robin -> #{robin.ga.inspect}")
      check.call('UTF-8 string encoding', robin.ga.to_s.encoding.name == 'UTF-8', robin.ga.to_s.encoding.name)
      # Irish specifically ships fadas — confirm one survives when Irish is the second language.
      if lang == 'ga'
        check.call('accented chars intact', chough.ga.to_s.include?('á'),
                   "chough -> #{chough.ga.inspect}")
      end
    else
      check.call('single-language station (no second-language labels needed)', true)
    end

    puts "\nlocale: external=#{Encoding.default_external}  LANG=#{ENV['LANG'].inspect}  RAILS_ENV=#{Rails.env}"
    abort("\nealta:doctor — FAILURES above") unless ok
    puts "\nall seams good ✓"
  end
end
