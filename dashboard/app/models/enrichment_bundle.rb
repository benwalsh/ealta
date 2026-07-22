# A day's enrichment for one species — an array of typed, cited blocks (see
# Enrichment::Block), produced by Enrichment::Builder (Claude) and consumed by every
# subscriber's Enrichment::Assembler (Nova), so a single cuckoo lookup serves the whole
# subscriber base. Stored per (sci_name, date), but facts & folklore are durable: the
# MOST RECENT bundle for a species stands as current on any later day until a refresh
# is due (see Enrichment::Policy's importance-keyed backoff), so we never re-derive the
# same house-sparrow facts day after day.
class EnrichmentBundle < ApplicationRecord
  # Default at the model, not the DB: MySQL forbids a literal default on a JSON column and the
  # SQLite schema dump can't round-trip an expression one, so `blocks` is `null: false` with no
  # DB default and starts as [] here.
  attribute :blocks, default: -> { [] }

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

    # A species' folklore, from BOTH sources treated identically: the station's own curated lore
    # (Enrichment::SeedLore ← bird_lore.yml) and the web-sourced folklore in the current bundle
    # (dúchas and friends). One uniform list of folklore Blocks, so a consumer never needs to know
    # which spring an entry came from. Seed lore is always present (no bundle required); Wikipedia
    # prose stays a `fact`, so it never appears here.
    def folklore_for(sci_name)
      Enrichment::SeedLore.blocks_for(sci_name) +
        Array(current(sci_name)&.block_objects).select { |b| b.type == 'folklore' }
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
    self.class.display(block_objects, date: date)
  end

  class << self
    # The card shape for a species, merging BOTH folklore springs into the same list the modal
    # already renders: the current bundle's sourced blocks (fact, regional note, web folklore) and
    # the station's own seed folklore (Enrichment::SeedLore ← bird_lore.yml), which needs no
    # bundle. Folklore is folklore here — a seed poem sits among the sourced blocks, credited the
    # same way. Nil when there's nothing to show.
    def display_for(sci_name)
      bundle = current(sci_name)
      display(Array(bundle&.block_objects) + Enrichment::SeedLore.blocks_for(sci_name),
              date: bundle&.date)
    end

    # Blocks → the card shape, or nil when none render.
    def display(blocks, date: nil)
      items = blocks.filter_map { |b| display_block(b) }
      return nil if items.empty?

      { date: (date || Date.current).iso8601, blocks: items }
    end

    private

    def display_block(block)
      attrs = block.to_h
      quote = attrs[:quote].presence
      # A curated verse-only entry has no prose `text` at all (its verse lives in `quote`), so it
      # must not be dropped for a blank text the way a genuinely empty block is.
      return nil if block.text.blank? && quote.blank?

      { type: block.type, text: block.text.presence, text_ga: block.text_ga.presence,
        # Curated literary lore (bird_lore.yml) carries more than a scraped passage — a title, a
        # set-apart verse, a context note, and a composed book credit — which ride through so the
        # species card can render the whole piece, just as the journal's Bird Lore & Wisdom does.
        title: attrs[:title].presence, quote: quote,
        note: attrs[:note].presence, credit: attrs[:credit].presence,
        # Keep a credit even when it has no URL — the station's seed lore cites an attribution
        # (e.g. "Ninth-century Irish poem"), not a link, and quoted material always says whence.
        # A dúchas source also carries its rights-holder, licence (+ deed link) and collector, so
        # the card can render the exact attribution the Schools' Collection asks for.
        sources: block.sources.filter_map { |source| display_source(source) } }
    end

    # A source is renderable once it can be pointed at — a link, or a bare attribution
    # (the seed lore's "Ninth-century Irish poem" has no URL). Fields come from the block
    # contract rather than being re-listed here, so a new citation field reaches the card
    # without a second edit in this file.
    def display_source(source)
      return nil unless source[:url].presence || source[:host].presence

      source.slice(*Enrichment::Block::SOURCE_FIELDS).compact
    end
  end
end
