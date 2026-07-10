class User < ApplicationRecord
  has_many :subscriptions, dependent: :destroy

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
end
