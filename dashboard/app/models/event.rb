# A noteworthy occurrence worth emailing about, recorded once per type+species+day
# (unique index). notified_at is nil until the alert email is sent; a failed send
# leaves it nil so the next ingest tick retries.
class Event < ApplicationRecord
  # The newsworthy kinds — a genuine "stop and look": a rarity, a first-ever, a
  # seasonal return. A followed-species event ('species') is personal, not news, so it
  # never appears on the public breaking strip.
  NEWS_TYPES = %w[rarity first_ever seasonal].freeze

  # The bilingual name for each newsworthy kind — the one wording the wall, the site's
  # breaking strip and the alert email all use, so "news" reads identically everywhere.
  # (BreakingNews.tsx carries the same words for the client strip.)
  KIND_LABEL = {
    'first_ever' => { en: 'First ever',      ga: 'Céaduair riamh' },
    'rarity'     => { en: 'Rarity',          ga: 'Annamh' },
    'seasonal'   => { en: 'Seasonal return', ga: 'Filleadh séasúrach' }
  }.freeze

  validates :event_type, :sci_name, :occurred_on, presence: true

  scope :pending, -> { where(notified_at: nil) }
  # The breaking strip: newsworthy events of the last couple of days, freshest first.
  scope :breaking, lambda { |on: Date.current, days: 2|
    where(event_type: NEWS_TYPES, occurred_on: (on - (days - 1))..on).
      order(occurred_on: :desc, id: :desc)
  }

  def mark_notified!
    update!(notified_at: Time.current)
  end

  # The kind's bilingual label, e.g. { en: 'Rarity', ga: 'Annamh' }.
  def kind_label
    KIND_LABEL[event_type] || { en: event_type, ga: event_type }
  end
end
