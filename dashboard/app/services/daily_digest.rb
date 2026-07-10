# Gathers a day's alert events into one email per user who chose the 'digest'
# cadence — the batched counterpart to AlertEngine's immediate sends. Idempotent per
# user+day (last_digest_on), so re-running never double-sends. Driven by the
# `ealta:digest` rake task, scheduled once a day (a morning digest of the previous
# complete day).
class DailyDigest
  class << self
    def deliver_all(date: Date.yesterday)
      return 0 unless Notifier.enabled?

      sent = 0
      candidates.find_each { |user| sent += 1 if new(user, date).deliver }
      sent
    end

    private

    # Only users who've set at least one subscription to the digest cadence.
    def candidates
      User.where(id: Subscription.active.digesting.select(:user_id))
    end
  end

  def initialize(user, date)
    @user = user
    @date = date
  end

  # Returns true only when an email actually went out.
  def deliver
    return false if @user.last_digest_on == @date

    facts = DigestFacts.for(user: @user, date: @date)
    # Mark the day done even when there's nothing to say — it's a complete past day,
    # nothing more will land, so there's no reason to rescan it.
    @user.update!(last_digest_on: @date)
    return false unless facts.any?

    Notifier.deliver_digest(user: @user, date: @date, facts: facts)
  end
end
