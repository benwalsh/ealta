class CreateSubscriptions < ActiveRecord::Migration[8.1]
  # A user's standing request to be emailed about detections: "tell me if you hear
  # a Corncrake" (alert_type 'species' + sci_name), or a standing rule with no
  # species like 'rarity' / 'first_ever'. Cloud-only in practice — the Pi has no
  # users — but the table is harmless on SQLite, so it's testable in dev.
  def change
    create_table :subscriptions do |t|
      # type: :bigint so the FK column matches users.id (bigint) on MySQL — SQLite makes every
      # integer 64-bit so it's silent there, but MySQL rejects an int→bigint FK (error 3780).
      t.references :user, null: false, foreign_key: true, type: :bigint
      t.string :alert_type, null: false, default: 'species'
      t.string :sci_name
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :subscriptions, %i[alert_type sci_name]
  end
end
