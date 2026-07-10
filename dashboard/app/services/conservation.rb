require 'json'

# BoCCI — Birds of Conservation Concern in Ireland (BirdWatch Ireland,
# 2020–2026): a Red / Amber / Green list of conservation priority for Ireland's
# regularly-occurring birds. Keyed by BirdNET scientific name in
# model/conservation_ie.json. Species that don't occur regularly in Ireland
# aren't assessed, so they simply have no status here.
class Conservation
  DATA_PATH = Rails.root.join('../model/conservation_ie.json')
  STATUSES = %w[red amber green].freeze

  # One-line gloss for the detail card, per status.
  NOTES = {
    'red'   => 'High conservation concern in Ireland',
    'amber' => 'Moderate conservation concern in Ireland',
    'green' => 'Least conservation concern in Ireland'
  }.freeze

  class << self
    # "red" | "amber" | "green", or nil when unlisted / unknown / no data yet.
    def status(sci)
      value = table[sci]
      STATUSES.include?(value) ? value : nil
    end

    # "Red" / "Amber" / "Green" for display, or nil.
    def name(sci)
      status(sci)&.capitalize
    end

    def note(sci)
      NOTES[status(sci)]
    end

    # BirdNET scientific names of the regularly-occurring Irish species — a sane
    # ~200-species set for the alert-subscription picker (vs all ~6000 BirdNET keys).
    def species
      table.keys
    end

    private

    def table
      @table ||= DATA_PATH.exist? ? JSON.parse(DATA_PATH.read) : {}
    end
  end
end
