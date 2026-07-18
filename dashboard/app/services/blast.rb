# A one-off note to the letter's readers — the rare "the station is off for a fortnight"
# message. Deliberately NOT part of the daily rhythm: the letter goes out on a schedule and
# nobody presses a button for it, whereas this exists precisely for the times a person needs
# to say something. That makes it the most dangerous thing in the console, so the ceremony
# around it (preview, a copy to yourself, then a typed confirmation naming the count) lives in
# AdminController and the console rather than here.
#
# The audience is exactly the letter's audience: people who ticked a box asking the station to
# email them. Nobody else is mailed, and the unsubscribe is the letter's own — see
# Notifier#deliver_blast.
class Blast
  class << self
    delegate :count, to: :recipients

    # Everyone on the letter cadence — the same set DailyLetter mails.
    def recipients
      User.where(id: Subscription.active.digesting.select(:user_id))
    end

    # Returns the number actually sent. A suppressed or failing address is skipped rather than
    # aborting the run, so one bad address can't stop the rest.
    def deliver_all(subject:, body:)
      return 0 unless Notifier.enabled?

      sent = 0
      recipients.find_each { |user| sent += 1 if Notifier.deliver_blast(user: user, subject: subject, body: body) }
      sent
    end
  end
end
