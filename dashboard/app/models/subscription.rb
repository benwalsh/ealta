# A user's standing alert request. 'species' subscriptions carry a sci_name
# ("email me if you hear a Corncrake"); 'rarity' / 'seasonal' / 'first_ever' are
# species-less standing rules. Email goes to the user's OAuth address. `cadence` is
# the "how": email immediately, batch into the daily digest, or stay silent.
class Subscription < ApplicationRecord
  # 'roundup' is the standalone daily letter — opt in and you get the narrated
  # station day even without following specific birds. It only ever arrives by
  # digest, so its cadence is immaterial.
  ALERT_TYPES = %w[species rarity first_ever seasonal roundup].freeze
  # immediate = email as it fires; digest = save for the daily roundup; off = no
  # email (a follow stays a follow, just silent).
  CADENCES = %w[immediate digest off].freeze

  delegate :email, to: :user
  belongs_to :user
  has_secure_token # :token — unguessable handle for unsubscribe links

  validates :alert_type, inclusion: { in: ALERT_TYPES }
  validates :cadence, inclusion: { in: CADENCES }
  validates :sci_name, presence: true, if: -> { alert_type == 'species' }

  scope :active, -> { where(active: true) }
  scope :for_species, ->(sci) { active.where(alert_type: 'species', sci_name: sci) }
  scope :of_type, ->(type) { active.where(alert_type: type) }
  scope :immediate, -> { where(cadence: 'immediate') }
  scope :digesting, -> { where(cadence: 'digest') }
end
