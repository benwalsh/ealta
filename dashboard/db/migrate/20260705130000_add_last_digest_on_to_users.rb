class AddLastDigestOnToUsers < ActiveRecord::Migration[8.1]
  # The date a user was last sent their daily digest — makes the digest run
  # idempotent (call it twice for the same day and the second is a no-op).
  def change
    add_column :users, :last_digest_on, :date
  end
end
