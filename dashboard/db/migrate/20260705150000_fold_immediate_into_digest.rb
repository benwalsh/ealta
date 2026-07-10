class FoldImmediateIntoDigest < ActiveRecord::Migration[8.1]
  # Immediate "alerts" (boolean, as-it-happens) are out of scope for now — a separate
  # concern from the daily email. Everything the station tells you now goes in the
  # daily email, so fold any existing immediate subscriptions into the digest cadence.
  def up
    execute("UPDATE subscriptions SET cadence = 'digest' WHERE cadence = 'immediate'")
  end

  def down
    # One-way: we don't restore the immediate cadence.
  end
end
