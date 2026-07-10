class CreateEvents < ActiveRecord::Migration[8.1]
  # The fire-once ledger of noteworthy occurrences (a first-ever species, a rarity,
  # a subscribed species heard). The unique index makes an event fire at most once
  # per type+species+day, so a Corncrake calling 40 times sends one email. notified_at
  # is the send/retry high-water mark: nil = not yet emailed; a failed send just stays
  # nil and the next ingest tick retries it (no queue needed).
  def change
    create_table :events do |t|
      t.string :event_type, null: false
      t.string :sci_name, null: false
      t.date :occurred_on, null: false
      t.datetime :notified_at
      t.timestamps
    end
    add_index :events, %i[event_type sci_name occurred_on], unique: true
  end
end
