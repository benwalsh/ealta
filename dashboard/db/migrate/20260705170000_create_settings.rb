class CreateSettings < ActiveRecord::Migration[8.1]
  # A tiny key/value store for the handful of things an admin changes at runtime (the
  # station's display language, so far) — settings that must not need a redeploy on an
  # unattended station box. Core to both runtimes, so NOT guarded to one adapter.
  def change
    return if table_exists?(:settings)

    create_table :settings do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :settings, :key, unique: true
  end
end
