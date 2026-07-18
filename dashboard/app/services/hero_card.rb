# The hero's deep-dive card — the day's featured bird, drawn ENTIRELY from already-sourced,
# cited material: its smart Wikipedia summary (SpeciesInfo). No new invention: Ruby assembles
# what was already sourced (precept 2). Shared by the web Journal and the letter, so both show
# the same card. nil when the day has no hero.
#
# The card used to carry the bundle's fact / regional-note blocks as a list too. It no longer
# does: those blocks are the raw material the day's NARRATION is written from (DayNarrator
# reads them straight off the bundle), so printing them underneath that narration repeated the
# same material in a flatter voice. Facts feed the prose; folklore is the set-apart coda quote.
# Nothing else consumed this field — the letter only ever read the descriptions.
class HeroCard
  class << self
    def for(sci_name)
      return nil if sci_name.blank?

      name = BirdName.lookup(sci_name)
      { sci: sci_name, en: name.en, ga: name.ga.presence,
        description: SpeciesInfo.english_for(sci_name, name.en),
        description_ga: SpeciesInfo.irish_for(sci_name, name.ga) }
    end
  end
end
