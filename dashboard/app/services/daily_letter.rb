# The Daily Letter — the completed day's JOURNAL entry, mailed to every subscriber on
# the letter (digest) cadence just after midnight station time (DailyEmailSweep, which
# has already sourced the day's enrichment and frozen the entry). The letter and the
# Journal page are the same words: one narration per day, written once, sent once.
# Idempotent per user+day (last_digest_on), so a retry never double-sends.
class DailyLetter
  class << self
    def deliver_all(date: Date.yesterday)
      return 0 unless Notifier.enabled?

      hero = hero_bird(date)
      sent = 0
      candidates.find_each { |user| sent += 1 if new(user, date, hero).deliver }
      sent
    end

    # The day's hero — the letter's featured bird — read from the frozen JournalEntry, so the
    # letter, the web coda and the deep dive all name the SAME bird (DayHero's importance +
    # anti-repetition pick, not a fresh recompute). `slug` carries the illustration only when the
    # station has art for that bird (the masks table is the truth of that); when it doesn't, the
    # letter runs without a picture until a sourced photo fills it. nil on a birdless day.
    def hero_bird(date)
      sci = JournalEntry.for(date)&.hero_sci_name
      return nil if sci.blank?

      name = BirdName.lookup(sci)
      slug = sci.downcase.tr(' ', '-')
      { sci: sci, slug: (slug if BirdMask.for(slug)),
        en: name.en, ga: name.ga.presence }
    end

    private

    # Everyone with at least one subscription on the letter cadence.
    def candidates
      User.where(id: Subscription.active.digesting.select(:user_id))
    end
  end

  def initialize(user, date, hero = nil)
    @user = user
    @date = date
    @hero = hero
  end

  # Returns true only when an email actually went out.
  def deliver
    return false if @user.last_digest_on == @date

    entry = JournalEntry.for(@date)
    # An UNSAVED entry is an outage/thin 'template' left for a later view to retry — nothing to send
    # yet, so mark done (a complete past day won't be rescanned). A PERSISTED entry is worth a
    # letter, even a frozen empty day: the reader still hears from the station, and the Notifier
    # gives that day a coverage-aware line (a quiet day, or the station was offline).
    unless entry&.persisted?
      @user.update!(last_digest_on: @date)
      return false
    end

    sent = Notifier.deliver_letter(user: @user, date: @date, entry: entry, hero: @hero)
    # Mark done ONLY on a confirmed send. A transient SES failure (deliver_letter → false) leaves
    # last_digest_on unset so the next sweep retries, rather than silently skipping this reader.
    @user.update!(last_digest_on: @date) if sent
    sent
  end
end
