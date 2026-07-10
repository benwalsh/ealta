# A tiny key/value store for the few settings an admin edits at runtime — things that
# shouldn't need a redeploy to change on an unattended box (the station's language, so
# far). One row per key; values are strings. Not cached: settings change rarely and the
# reads are trivial, so a per-process cache would only risk stale reads across workers.
class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  class << self
    def get(key, default = nil)
      where(key: key.to_s).pick(:value) || default
    end

    def set(key, value)
      find_or_initialize_by(key: key.to_s).update!(value: value.to_s)
      value
    end
  end
end
