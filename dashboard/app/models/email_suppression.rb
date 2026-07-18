# A per-address delivery block, fed by SES bounce/complaint notifications (SNS →
# SesNotificationsController). A suppressed address is never emailed again: the
# Notifier skips it before every send, so a hard bounce or a spam complaint can't
# keep costing us SES sending reputation.
#
# Hard bounces and complaints suppress on the FIRST event and stay permanent; a
# transient (soft) bounce only suppresses after SOFT_BOUNCE_LIMIT of them in a row,
# and any confirmed delivery resets that streak (it's "consecutive").
class EmailSuppression < ApplicationRecord
  # Consecutive soft bounces we tolerate before giving up on an address.
  SOFT_BOUNCE_LIMIT = 5

  validates :email, presence: true, uniqueness: true

  scope :active, -> { where.not(suppressed_at: nil) }

  class << self
    def suppressed?(email)
      active.exists?(email: normalize(email))
    end

    # Every currently-blocked address — for filtering a recipient set in one query.
    def suppressed_emails
      active.pluck(:email)
    end

    def record_hard_bounce!(email)
      block!(email, 'hard_bounce')
    end

    def record_complaint!(email)
      block!(email, 'complaint')
    end

    # A transient failure: count it, and block once we've seen too many with no
    # delivery in between.
    def record_soft_bounce!(email)
      row = for_email(email)
      row.soft_bounces += 1
      row.block('soft_bounce') if row.soft_bounces >= SOFT_BOUNCE_LIMIT
      row.save!
    end

    # A confirmed delivery clears the soft-bounce streak.
    def record_delivery!(email)
      find_by(email: normalize(email))&.update!(soft_bounces: 0)
    end

    def normalize(email)
      email.to_s.strip.downcase
    end

    private

    def block!(email, reason)
      row = for_email(email)
      row.block(reason)
      row.save!
    end

    def for_email(email)
      find_or_initialize_by(email: normalize(email))
    end
  end

  # Mark blocked. Idempotent and first-write-wins: the original reason and time
  # stand even if later events arrive, so "permanent on first occurrence" holds.
  def block(reason)
    return if suppressed_at?

    self.reason = reason
    self.suppressed_at = Time.current
  end
end
