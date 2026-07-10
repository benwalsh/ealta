class AddCadenceToSubscriptions < ActiveRecord::Migration[8.1]
  # How a user wants this subscription delivered: 'immediate' (email as it fires),
  # 'digest' (batch into the daily roundup), or 'off' (no email — for follows, still
  # following, just silent). The "what" is alert_type/sci_name; this is the "how".
  def change
    add_column :subscriptions, :cadence, :string, null: false, default: 'immediate'
  end
end
