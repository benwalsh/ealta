class CreateJournalEntries < ActiveRecord::Migration[8.1]
  # One frozen diary entry per completed day: the day's narration (bilingual bullets) and the
  # citations behind its facts & folklore. A completed day is immutable, so it is narrated once
  # — by the daily sweep, or lazily on first view — and never regenerated, unlike TodaySummary's
  # single rolling slot. Figures and the sparkline are recomputed from the (immutable) detections
  # on read, so only the model's prose is stored. Runs on both the Pi and the cloud mirror.
  def change
    create_table :journal_entries do |t|
      t.date :date, null: false
      t.json :bullets, null: false, default: -> { '(JSON_OBJECT())' } # { en: [...], ga: [...] }
      t.string :source # 'llm' | 'facts' | 'template'
      t.json :sources, null: false, default: -> { '(JSON_ARRAY())' } # [{ host:, url: }]
      t.timestamps
    end
    add_index :journal_entries, :date, unique: true
  end
end
