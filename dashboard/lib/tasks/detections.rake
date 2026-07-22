# frozen_string_literal: true

# Remove ALL records for one or more species — detections AND their derived events — from
# whatever database this environment points at: the on-device SQLite, or the cloud MySQL mirror
# when run with the cloud config (RAILS_ENV=cloud + DB_* set). Built for pruning BirdNET false
# positives — a species the station cannot actually have heard (a Common Crane on this coast, a
# Black Woodpecker anywhere in Ireland) that still accrues detections and can fire a
# 'rarity'/'first_ever' alert precisely because it looks unusual.
#
# SAFE BY DEFAULT: a dry run that only COUNTS and prints. Nothing is deleted until CONFIRM=DELETE
# (the same typed word the admin "start fresh" wipe uses). Journal entries are deliberately left
# untouched — they are frozen daily prose, a historical record rather than a live view; if a
# purged bird was named in a day's narrative, regenerate that day from /admin.
#
#   # see what WOULD go (no writes):
#   bin/rails detections:remove_species \
#     SPECIES='Tawny Owl, Black Woodpecker, Crested Tit, Common Crane, Eurasian Green Woodpecker'
#
#   # actually delete (typed confirmation):
#   bin/rails detections:remove_species SPECIES='Tawny Owl, Common Crane' CONFIRM=DELETE
#
# Names are matched case-insensitively against BOTH Com_Name and Sci_Name, so either the common
# name ('Common Crane') or the scientific name ('Grus grus') resolves the same rows. A name that
# matches nothing is REPORTED, not silently skipped — check it against the dry run before
# confirming, since the cloud may spell a bird differently than you typed.
namespace :detections do
  desc "Delete all detections + events for SPECIES='Name, Other Name' (dry run unless CONFIRM=DELETE)"
  task remove_species: :environment do
    confirm_word = 'DELETE'
    names = ENV['SPECIES'].to_s.split(',').map(&:strip).reject(&:empty?)
    if names.empty?
      example = "bin/rails detections:remove_species SPECIES='Common Crane, Tawny Owl'"
      abort "give the species to remove, comma-separated:\n  #{example}"
    end

    confirmed = ENV['CONFIRM'].to_s == confirm_word
    cfg = ActiveRecord::Base.connection_db_config
    mode = if confirmed
             'DELETE — the rows below will be permanently removed'
           else
             'dry run — nothing is deleted (add CONFIRM=DELETE to delete)'
           end
    puts "database: #{cfg.adapter} #{cfg.database}   (#{Detection.count} detections total)"
    puts "MODE: #{mode}"
    puts

    # Resolve each requested name to its rows independently, so the report shows which of the
    # names actually hit — a misspelling or an absent bird stands out instead of vanishing.
    matched_scis = []
    total_det = total_evt = 0

    names.each do |name|
      down = name.downcase
      dets = Detection.where('LOWER(Com_Name) = ? OR LOWER(Sci_Name) = ?', down, down)
      d_count = dets.count
      if d_count.zero?
        puts format('  %-34s  no rows match (check the spelling)', name)
        next
      end

      scis = dets.distinct.pluck(:Sci_Name)
      e_count = Event.where(sci_name: scis).count
      matched_scis.concat(scis)
      total_det += d_count
      total_evt += e_count
      puts format('  %-34s  %5d detections, %3d events   [%s]', name, d_count, e_count, scis.join(', '))
    end

    matched_scis.uniq!
    puts
    puts "totals: #{total_det} detections, #{total_evt} events across #{matched_scis.size} species"

    if total_det.zero? && total_evt.zero?
      puts 'nothing to delete.'
      next
    end

    unless confirmed
      puts
      puts 'dry run only — re-run with CONFIRM=DELETE to remove these. Back up first:'
      puts '  SQLite:  bin/rails db:dump        cloud/MySQL:  take an RDS snapshot'
      next
    end

    # One transaction: either both tables lose the species or neither does, so a mid-delete
    # failure can't leave an orphaned event pointing at a bird whose detections are gone.
    lowered = names.map(&:downcase)
    ActiveRecord::Base.transaction do
      d = Detection.where('LOWER(Com_Name) IN (?) OR LOWER(Sci_Name) IN (?)', lowered, lowered).delete_all
      e = Event.where(sci_name: matched_scis).delete_all
      puts "deleted #{d} detections and #{e} events."
    end
  end
end
