class AddTokenToSubscriptions < ActiveRecord::Migration[8.1]
  # Unguessable handle for one-click email unsubscribe links (has_secure_token),
  # so an unsubscribe URL can't be forged from a sequential id.
  def change
    add_column :subscriptions, :token, :string
    add_index :subscriptions, :token, unique: true
  end
end
