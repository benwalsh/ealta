class User < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_secure_token :letter_token # unguessable handle for the daily letter's one-click unsubscribe

  validates :provider, :uid, presence: true

  class << self
    # Find-or-create from an OmniAuth callback, refreshing the profile each sign-in.
    def from_omniauth(auth)
      find_or_initialize_by(provider: auth.provider, uid: auth.uid).tap do |user|
        user.email = auth.info.email
        user.name = auth.info.name
        user.avatar_url = auth.info.image
        user.save!
      end
    end
  end

  # Admin gating for later (Station settings et al.): if ADMIN_EMAILS is set, only
  # those addresses are admins; if it's unset, no one is (fail-closed).
  def admin?
    emails = ENV.fetch('ADMIN_EMAILS', '').split(',').map { |e| e.strip.downcase }.reject(&:empty?)
    emails.include?(email.to_s.downcase)
  end

  def display_name
    name.presence || email
  end

  # One-click unsubscribe from the daily letter: drop out of the letter's recipient
  # set without unfollowing anything. The roundup opt-in is switched off, and any
  # species follow that was riding the digest goes silent (still followed) — the same
  # "off" state the account toggle uses. Idempotent.
  def unsubscribe_from_letter!
    # rubocop:disable Rails/SkipsModelValidations
    subscriptions.where(alert_type: 'roundup').update_all(active: false)
    subscriptions.active.digesting.update_all(cadence: 'off')
    # rubocop:enable Rails/SkipsModelValidations
  end
end
