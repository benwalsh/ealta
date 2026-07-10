# A day's enrichment for one species — an array of typed, cited blocks (see
# Enrichment::Block), produced by Enrichment::Builder (Claude) and consumed by every
# subscriber's Enrichment::Assembler (Nova), so a single cuckoo lookup serves the whole
# subscriber base. Stored per (sci_name, date), but facts & folklore are durable: the
# MOST RECENT bundle for a species stands as current on any later day until a refresh
# is due (see Enrichment::Policy's importance-keyed backoff), so we never re-derive the
# same house-sparrow facts day after day.
class EnrichmentBundle < ApplicationRecord
  validates :sci_name, presence: true, uniqueness: { scope: :date }
  validates :date, presence: true

  scope :for_date, ->(date) { where(date: date) }

  class << self
    # The current (most recent) bundle for one species, or nil.
    def current(sci_name)
      where(sci_name: sci_name).order(date: :desc).first
    end

    # The current bundle for each of several species — the catalogue an assembler
    # reads, drawing each bird's latest enrichment whatever day it was sourced.
    def current_for(sci_names)
      where(sci_name: sci_names).order(date: :desc).uniq(&:sci_name)
    end
  end

  # The stored blocks as validated value objects. Invalid blocks are dropped — a
  # bundle only ever hands the assembler blocks that honour the contract.
  def block_objects
    Array(blocks).filter_map { |raw| Enrichment::Block.from(raw) }.select(&:valid?)
  end

  # The card-facing shape: every sourced block (fact, the local "in Ireland" note,
  # folklore) in order, each with its citations — so the card shows all of what Claude
  # found, not just one line. Nil when there's nothing usable. Shared by the species API
  # and the on-demand look-up so the card renders one consistent object.
  def to_display
    items = block_objects.filter_map { |b| display_block(b) }
    return nil if items.empty?

    { date: date.iso8601, blocks: items }
  end

  private

  def display_block(block)
    return nil if block.text.blank?

    { type: block.type, text: block.text, text_ga: block.text_ga.presence,
      sources: block.sources.filter_map { |s| s[:url].presence && { host: s[:host], url: s[:url] } } }
  end
end
