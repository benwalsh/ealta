# One user's day, as a facts object — the personal slice the digest narrates. Ruby
# computes every fact here; DigestSummary (the LLM) only phrases it, and the mechanical
# email renders the same object. Nothing about a user's day is ever invented.
#
#   follows  — the birds THEY follow that were heard today, with verbatim counts
#   alerts   — standing-rule events (rarity/seasonal/first-ever) they take by digest
#   roundup  — the general station day (DailyFacts), only if they opted into the letter
class DigestFacts
  Result = Struct.new(:date, :follows, :alerts, :roundup, keyword_init: true) do
    # Something worth sending: a followed bird turned up, an alert fired, or they
    # asked for the daily letter regardless.
    def any?
      follows.any? || alerts.any? || !roundup.nil?
    end
  end

  class << self
    def for(user:, date: Date.yesterday)
      new(user, date).build
    end
  end

  def initialize(user, date)
    @user = user
    @date = date
  end

  def build
    Result.new(date: @date, follows: follows_heard, alerts: alert_items, roundup: roundup_facts)
  end

  private

  # Credible follows heard that day (via the same tally the site uses — no low-
  # confidence blip counts), with their call counts.
  def follows_heard
    wanted = digesting.where(alert_type: 'species').pluck(:sci_name).to_set
    return [] if wanted.empty?

    Detection.tally_for(@date).filter_map do |tally|
      next unless wanted.include?(tally.sci_name)

      { sci: tally.sci_name, en: tally.name.en, ga: tally.name.ga, count: tally.count }
    end
  end

  # Standing-rule events the user receives by digest, that actually fired today.
  def alert_items
    types = digesting.where(alert_type: %w[rarity seasonal first_ever]).pluck(:alert_type)
    return [] if types.empty?

    Event.where(occurred_on: @date, event_type: types).map do |event|
      name = BirdName.lookup(event.sci_name)
      { kind: event.event_type, sci: event.sci_name, en: name.en, ga: name.ga }
    end
  end

  # The general station day — only for users who opted into the daily letter.
  def roundup_facts
    return nil unless @user.subscriptions.active.exists?(alert_type: 'roundup')

    DailyFacts.for(date: @date)
  end

  def digesting
    @digesting ||= @user.subscriptions.active.digesting
  end
end
