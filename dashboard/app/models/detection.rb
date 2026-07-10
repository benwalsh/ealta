class Detection < ApplicationRecord
  # One row per species heard, with its call count, latest time, and best
  # confidence — the shape the collage and stats consume. Loudest-first.
  SpeciesTally = Data.define(:sci_name, :count, :last_time, :confidence) do
    def name = BirdName.lookup(sci_name)
  end

  # A species' whole history, for the atlas / life list.
  LifeEntry = Data.define(:sci_name, :count, :first_seen, :last_seen) do
    def name = BirdName.lookup(sci_name)
  end

  # A species earns a place on the wall once we trust it: either one confident
  # hit, or enough repeats to rule out a one-off. Rare + low-confidence (a lone
  # 27% "Gadwall") is exactly BirdNET's false-positive zone, so it stays hidden.
  CREDIBLE_CONFIDENCE = 0.6
  CREDIBLE_COUNT = 5

  # birds.db uses capitalised column names; expose snake_case for ergonomics.
  alias_attribute :sci_name, :Sci_Name
  alias_attribute :com_name, :Com_Name
  alias_attribute :confidence, :Confidence

  validates :Sci_Name, presence: true
  validates :Com_Name, presence: true

  scope :on_date, ->(date) { where(Date: date) }
  scope :today, -> { on_date(Date.current) }
  # Detections within the last `hours` (a huge value means "all time").
  scope :within, ->(hours) { hours >= 1_000_000 ? all : since(hours.to_f.hours.ago) }
  scope :since, ->(time) { where("#{when_sql} >= ?", time.strftime('%Y-%m-%d %H:%M:%S')) }

  # The detection's actual moment, combining the separate Date and Time columns.
  def heard_at
    date = self[:Date]
    time = self[:Time]
    return nil unless date && time

    Time.zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
  end

  class << self
    # Adapter-aware chronological key: the separate Date + Time columns normalised
    # into one sortable "YYYY-MM-DD HH:MM:SS" string. On the Pi (SQLite) date()/
    # time() cope with both our dev format ("2000-01-01 HH:MM:SS") and the real
    # birds.db format ("HH:MM:SS"). In the cloud mirror (MySQL) we need CONCAT +
    # backticks — there `||` is boolean OR, and Date/Time in double quotes are
    # string literals, not identifiers. This is the ONE cross-database seam.
    def when_sql
      if connection.adapter_name.match?(/sqlite/i)
        %{date("Date") || ' ' || time("Time")}
      else
        "CONCAT(DATE(`Date`), ' ', TIME(`Time`))"
      end
    end

    def tally_for(date = Date.current)
      tally(on_date(date))
    end

    def tally_within(hours)
      tally(within(hours))
    end

    # Sci_Names we trust enough to display, assessed over all time (a real
    # visitor stays credible even in a quiet window). See CREDIBLE_CONFIDENCE.
    def credible_species
      group(:Sci_Name).
        having('MAX(Confidence) >= :conf OR COUNT(*) >= :hits', conf: CREDIBLE_CONFIDENCE, hits: CREDIBLE_COUNT).
        pluck(:Sci_Name).to_set
    end

    # One SpeciesTally per credible species in the relation, loudest-first.
    def tally(relation)
      credible = credible_species
      relation.
        group(:Sci_Name).
        pluck(Arel.sql("Sci_Name, COUNT(*), MAX(#{when_sql}), MAX(Confidence)")).
        map { |sci, count, last, confidence| SpeciesTally.new(sci, count.to_i, last, confidence.to_f) }.
        select { |species| credible.include?(species.sci_name) }.
        sort_by { |species| -species.count }
    end

    # Every credible species ever heard, with totals and first/last timestamps.
    def life_list
      credible = credible_species
      group(:Sci_Name).
        pluck(Arel.sql("Sci_Name, COUNT(*), MIN(#{when_sql}), MAX(#{when_sql})")).
        map { |sci, count, first, last| LifeEntry.new(sci, count.to_i, first, last) }.
        select { |entry| credible.include?(entry.sci_name) }
    end

    # Newest additions to the life list (most recently first-heard species).
    def first_detections(limit = 8)
      life_list.sort_by(&:first_seen).reverse.first(limit)
    end

    # Detection counts in named recency buckets, for the stats "By Period" list.
    def by_period
      [['Past hour', 1], ['Past 24 hours', 24], ['Past 7 days', 168], ['All time', 1_000_000]].
        map { |label, hours| [label, within(hours).count] }
    end
  end
end
