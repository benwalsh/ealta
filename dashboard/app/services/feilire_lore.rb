# The day's NARRATIVE lore — the saint(s), verse and story for a calendar day, from the station's
# curated felire_lore.yml (the Martyrology of Óengus, Stokes 1905, and companions). This sits
# beside the factual Feilire exactly as SeedLore (bird_lore.yml) sits beside the bird data: Feilire
# supplies the day's NAME and kind (which the model may never guess); FeilireLore supplies the
# quoted, attributed day-lore that fills the Journal's day-section. The model never writes these —
# the render layer quotes them with their credit. A day with no entry has none; the Journal falls
# back to the Celtic season (see Feilire), never to a blank.
class FeilireLore
  # A machine-extracted day with no clean text carries this marker instead — it must fall
  # through to the next layer (the season), never render (see CLAUDE.md §0).
  SOURCE_GAP = /\A\[SOURCE GAP/

  class << self
    # The featured day-lore for a date as a ready display hash, or nil when the day has no usable
    # entry (an eight-of-366 source gap, or a day the calendar doesn't cover — either way the
    # Journal falls back to the Celtic season).
    #   text        — what to show: the legible `gloss` where present, else the `quatrain` (most of
    #                 the 366 machine-extracted days carry only the quatrain). Never a SOURCE-GAP
    #                 marker or a blank.
    #   verse       — true when the text is a self-standing quatrain the entry promoted to lead —
    #                 set it in the voice-italic. A quatrain shown only because there's no gloss
    #                 stays prose (it's the plain floor line, not a featured verse).
    #   quatrain_ga — the Old Irish, surfaced ONLY when ga_verified: an unverified transcription is
    #                 a silent-failure risk, so it stays hidden until a fluent reader clears the flag.
    #   credit      — a composed provenance line (the entry's own source, else the file's _meta).
    def for(date)
      entry = lookup(date)
      return nil unless entry.is_a?(Hash)

      gloss    = clean(entry['gloss'])
      quatrain = clean(entry['quatrain'])
      return nil if gloss.nil? && quatrain.nil? # a SOURCE GAP or empty day → season fallback

      verse = entry['lead'] == 'quatrain' && !quatrain.nil?
      {
        saints:      Array(entry['saints']).map { |s| s.to_s.strip }.reject(&:empty?),
        text:        verse ? quatrain : (gloss || quatrain),
        verse:       verse,
        quatrain_ga: verified_ga(entry),
        note:        clean(entry['note']),
        credit:      credit_for(entry)
      }
    end

    private

    # A field's usable text, or nil when it is blank or a source-gap placeholder.
    def clean(str)
      s = str.to_s.strip
      s.presence unless s.match?(SOURCE_GAP)
    end

    def data
      StationProfile.yaml('content/felire_lore.yml')
    end

    # Shared provenance for every entry, overridden per entry where a second source is named.
    def meta
      data['_meta'].is_a?(Hash) ? data['_meta'] : {}
    end

    # A day maps to a LIST of entries (chief first); the first is the one the day-section features.
    # A lone hash (not a list) is tolerated so a single-entry day can skip the array.
    def lookup(date)
      raw = data[date.strftime('%m-%d')]
      raw.is_a?(Array) ? raw.first : raw
    end

    # The Old Irish quatrain, only once a human has verified the transcription (ga_verified: true).
    def verified_ga(entry)
      return nil unless entry['ga_verified'] == true

      entry['quatrain_ga'].to_s.strip.presence
    end

    # "The Martyrology of Óengus …, trans. Whitley Stokes (1905)" — attribution (if any), then the
    # source work with its translator/editor and year, from the entry or the shared _meta.
    def credit_for(entry)
      work   = value(entry, 'source_work')
      editor = value(entry, 'editor')
      year   = entry['year_translation'] || entry['year'] || meta['year_translation'] || meta['year']
      book   = work && editor ? "#{work}, trans. #{editor}" : (work || editor)
      book   = "#{book} (#{year})" if book && year
      [entry['attribution'].to_s.strip.presence, book].compact.join(' · ').presence
    end

    def value(entry, key)
      (entry[key] || meta[key]).to_s.strip.presence
    end
  end
end
