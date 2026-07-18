# The station's own note on a day — a line from the keeper that rides along with that day's
# letter AND its journal entry (the letter and the journal are the same words, so a note that
# appeared in only one would split them).
#
# Its own table rather than a column on journal_entries, for two reasons: rebuilding a journal
# destroys and recreates the row (AdminController#regenerate_journal), which would take the
# note with it; and a note has to be writable BEFORE the day's entry exists, since the entry is
# only frozen by the 00:15 sweep — otherwise you could never write a note ahead of the letter.
#
# Additive and legal on both engines (SQLite on-device, MySQL in the cloud): no literal default
# on the text column (MySQL 1101).
class CreateDayNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :day_notes do |t|
      t.date :date, null: false
      t.text :body
      t.timestamps
    end
    add_index :day_notes, :date, unique: true
  end
end
