# Deliverability plumbing for SES: a per-user token for the daily letter's one-click
# unsubscribe, and a suppression list fed by SES bounce/complaint notifications.
# Additive and legal on both engines (SQLite on-device, MySQL in the cloud) — plain
# scalar defaults only, no JSON/TEXT literal defaults (MySQL 1101).
class AddEmailDeliverability < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :letter_token, :string
    add_index  :users, :letter_token, unique: true

    # Backfill existing users so every account already has a working unsubscribe handle
    # (has_secure_token only mints one on create). Same alphabet/length as has_secure_token.
    User.reset_column_information
    User.where(letter_token: nil).find_each do |user|
      user.update_columns(letter_token: SecureRandom.base58(24)) # rubocop:disable Rails/SkipsModelValidations
    end

    create_table :email_suppressions do |t|
      t.string   :email, null: false
      t.string   :reason # 'hard_bounce' | 'soft_bounce' | 'complaint'
      t.integer  :soft_bounces, null: false, default: 0
      t.datetime :suppressed_at # nil until actually blocked
      t.timestamps
    end
    add_index :email_suppressions, :email, unique: true
  end

  def down
    drop_table :email_suppressions
    remove_index :users, :letter_token
    remove_column :users, :letter_token
  end
end
