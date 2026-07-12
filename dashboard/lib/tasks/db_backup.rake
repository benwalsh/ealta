# frozen_string_literal: true

# Back up / restore the on-device SQLite. Detections and enrichment are runtime data (the
# storage/ file is gitignored), so a dump is the only copy that isn't the cloud mirror — worth
# taking before anything destructive (a re-provision, a risky migration, wiping local data).
# SQLite-only: the cloud MySQL mirror is backed up by RDS snapshots, not this.
namespace :db do
  desc 'Back up the SQLite database to a timestamped file (dir: BACKUP_DIR, default storage/backups/)'
  task dump: :environment do
    db = ActiveRecord::Base.connection_db_config.database.to_s
    unless db.end_with?('.sqlite3')
      abort "db:dump is SQLite-only; this environment uses #{ActiveRecord::Base.connection.adapter_name}"
    end

    dir = ENV.fetch('BACKUP_DIR', Rails.root.join('storage/backups').to_s)
    FileUtils.mkdir_p(dir)
    dest = File.join(dir, "#{File.basename(db, '.sqlite3')}-#{Time.zone.now.strftime('%Y%m%d-%H%M%S')}.sqlite3")

    # Fold the WAL into the main file first, so the plain copy is consistent even while the
    # listener is writing.
    ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    FileUtils.cp(db, dest)
    puts "db:dump  #{db}  ->  #{dest}  (#{Detection.count} detections)"
  end

  desc 'Restore the SQLite database from a backup:  rake db:restore FILE=path/to/backup.sqlite3'
  task restore: :environment do
    file = ENV['FILE'].to_s
    abort 'give the backup to restore:  rake db:restore FILE=path/to/backup.sqlite3' if file.empty?
    abort "not found: #{file}" unless File.exist?(file)

    db = ActiveRecord::Base.connection_db_config.database.to_s
    unless db.end_with?('.sqlite3')
      abort "db:restore is SQLite-only; this environment uses #{ActiveRecord::Base.connection.adapter_name}"
    end

    ActiveRecord::Base.connection_pool.disconnect! # release the file before overwriting it
    FileUtils.cp(file, db)
    puts "db:restore  #{db}  <-  #{file}  (stop the app first; it reopens the file on next boot)"
  end
end
