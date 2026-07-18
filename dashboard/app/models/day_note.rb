# A line from the keeper for a given day, carried by both that day's letter and its journal
# entry. Kept apart from JournalEntry on purpose — see the migration: rebuilding a journal
# would destroy a note stored on it, and a note must be writable before the day's entry exists.
#
# Blank is the same as absent: saving an empty box clears the note rather than storing "".
class DayNote < ApplicationRecord
  validates :date, presence: true, uniqueness: true

  class << self
    # The note for a day, or nil. The one reader the letter and the journal both go through.
    def body_for(date)
      find_by(date: date)&.body.presence
    end

    # Write or clear a day's note. Returns the stored body (nil when cleared).
    def write(date:, body:)
      note = find_or_initialize_by(date: date)
      if body.to_s.strip.empty?
        note.destroy if note.persisted?
        return nil
      end
      note.update!(body: body.to_s.strip)
      note.body
    end
  end
end
