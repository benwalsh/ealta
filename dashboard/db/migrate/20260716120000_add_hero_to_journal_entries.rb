class AddHeroToJournalEntries < ActiveRecord::Migration[8.1]
  # The day's ONE hero bird (its scientific name), frozen with the entry so the letter, the web
  # coda and any later view feature the SAME bird. Chosen by DayHero — importance-first, but with
  # a memory, so an everyday bird doesn't lead every quiet day (see DayHero). Nullable: a birdless
  # day has no hero, and existing rows backfill as nil. Additive and legal on SQLite and MySQL.
  def change
    add_column :journal_entries, :hero_sci_name, :string
  end
end
