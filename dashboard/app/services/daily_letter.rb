# The Daily Letter — the completed day's JOURNAL entry, mailed to every subscriber on
# the letter (digest) cadence just after midnight station time (DailyEmailSweep, which
# has already sourced the day's enrichment and frozen the entry). The letter and the
# Journal page are the same words: one narration per day, written once, sent once.
# Idempotent per user+day (last_digest_on), so a retry never double-sends.
class DailyLetter
  class << self
    def deliver_all(date: Date.yesterday)
      return 0 unless Notifier.enabled?

      sent = 0
      candidates.find_each { |user| sent += 1 if new(user, date).deliver }
      sent
    end

    private

    # Everyone with at least one subscription on the letter cadence.
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

    entry = JournalEntry.for(@date)
    # Mark the day done even when there's nothing to say — it's a complete past day,
    # nothing more will land, so there's no reason to rescan it.
    @user.update!(last_digest_on: @date)
    # An unsaved entry is the thin 'template' narration (nothing to say, or a model
    # outage left for a later view to retry) — not worth a letter.
    return false unless entry&.persisted?

    Notifier.deliver_letter(user: @user, date: @date, entry: entry)
  end
end
