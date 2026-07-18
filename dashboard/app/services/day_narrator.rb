# Narrates a single day into warm, factual bullets that read like a naturalist's diary entry,
# not a stats readout — the LENGTH scaling with how much actually happened (a quiet sparrows-and-
# gulls day stays brief; a day of arrivals and rarities runs fuller and features each notable
# bird). Given a DailyFacts hash for ANY day (today, or a completed past day for the Journal), it
# returns bilingual bullets + their source + the citations behind the facts & folklore, opening on
# the day's HERO (DayHero — importance with anti-repetition), so the prose leads with the same bird
# the letter pictures and the coda quotes. Ruby has already done the reasoning (DailyFacts for the
# day's shape; EnrichmentBundle for each prominent bird's already-sourced facts & folklore); this
# layer only asks the model to STITCH that material, and falls back to a rich no-model version when
# the model is unavailable. Date-agnostic and stateless: TodaySummary wraps it with the today
# cache, JournalEntry wraps it with a frozen per-day store.
class DayNarrator
  # The daily-note system prompt is the station's own (Prompts -> day_note.system.md); the
  # location is filled per request (%<where>s). Ruby still owns every fact it narrates.

  # How many items to hand the model — ordered importance-first, so the tail of
  # routine tallies is bounded without hiding anything that matters.
  MAX_ITEMS = 10
  # The ceiling on bullets — a full day of rarities earns the longer end; the target for any given
  # day is set by DailyFacts' notable count (see target_bullets), and the model is told the range.
  MAX_BULLETS = 5
  # The day's hero, phrased from its flag, for the LEAD line (mirrors DailyFacts' rarity_context).
  HERO_CONTEXT = {
    'all_time_first'       => 'a first for the station',
    'all_time_first_young' => 'a first for the station',
    'year_first'           => 'the first this year',
    'rare_local'           => 'a locally rare visitor'
  }.freeze
  # How many of the day's most prominent species to pull stored facts & folklore for.
  LORE_SPECIES = 5
  # How many un-enriched NOTABLE birds a single pass will source on the spot.
  ENRICH_ON_REFRESH = 3
  ACTIVITY_PHRASES = {
    'quieter_than_typical' => 'quieter than typical',
    'typical'              => 'typical',
    'busier_than_typical'  => 'busier than typical'
  }.freeze

  # The flags that make "first"/"arrival" language truthful.
  ARRIVAL_FLAGS = %w[all_time_first all_time_first_young year_first].freeze
  # Words that assert novelty — legitimate only when the facts actually flag an arrival.
  NOVELTY = /\b(first|arriv\w+|debut|maiden|newly)\b/i

  # A count is how many TIMES a bird was heard, not how many birds — the station records
  # sounds and cannot count individuals, so one bird calling all morning is many detections.
  # "two birds logged" is therefore false, and it is the easiest falsehood for a narrator to
  # reach for. The prompt says so; this refuses the bullet if it does it anyway, because a
  # confidently wrong bird fact is the failure that matters. Matches a number (in digits or
  # words) attached to "bird(s)": "two birds", "137 birds", "a dozen birds".
  COUNTED_BIRDS = /
    \b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|
       dozen|several|a\s+few|many|numerous)\s+
    (?:\w+\s+){0,2}?birds?\b
  /xi
  # …but a NEGATED mention ("no new arrivals or firsts today") is not a claim.
  NEGATION = /\b(no|not|n't|without|never|nothing|none|nor)\b/i

  # The daily voice is the most-read, most-embarrassing-if-wrong text in the app, so it
  # narrates and translates with the stronger Claude model (the enrichment model), not Nova
  # Lite (which conflated importance with loudness and mangled the Gaeilge). A lambda so an
  # ENRICH_MODEL_ID override is picked up at call time, not load time.
  NARRATOR_MODEL = -> { Bedrock.enrich_model_id }
  NARRATOR_TOKENS = 700
  # The dry, encyclopedic kind of fact the no-model fallback skips in favour of a
  # behaviour/voice/habit fact or folklore. Single stems only (no literal spaces).
  DULL_FACT = /\b(identif|resembl|distinguish|plumage|juvenile|eyes?|feather|widely|
                  distribut|inhabit|habitat|taxonom|subspecies|measur|weigh|wingspan|centimet)/ix
  # Flags the no-model fallback treats as genuine news (a real first). all_time_first_young
  # is deliberately excluded — in a young station everything is a "first", so it's damped.
  NEWS_FLAGS = %w[all_time_first year_first].freeze
  NEWS_LABEL = {
    en: { all_time_first: 'New for the station', year_first: 'First of the year' },
    ga: { all_time_first: 'Nua ag an stáisiún', year_first: 'Céaduair i mbliana' }
  }.freeze
  # Appended when narrating a COMPLETED past day (the Journal), so the finished day reads in
  # retrospect — "today"/"so far" belong only to the in-progress day the front page shows.
  COMPLETED_DAY_NOTE = 'This entry is for a COMPLETED day (the Date above), written in ' \
                       'retrospect. Use the PAST TENSE throughout — "led the day", "was heard", ' \
                       '"arrived". Do NOT write "today" or "so far"; the day is finished.'.freeze

  class << self
    # Narrate a day → { bullets: { en:, ga: }, source: 'llm'|'facts'|'template', sources: [...] }.
    # Stateless and date-agnostic — the caller decides how to cache/freeze it.
    #   model:  false → skip the model entirely, return the rich fallback (the never-block path)
    #   enrich: true  → source the day's un-enriched notable birds first (slow; the build path)
    # 'llm' means the model wrote it; 'facts'/'template' mean it fell back (model off/failed).
    def narrate(facts, model: true, enrich: false, hero: nil)
      ensure_notable_enriched(facts) if enrich && model
      # The day's hero leads the prose. The caller (JournalEntry) passes the pick it froze so the
      # note, the picture and the coda agree; other callers let us resolve it here.
      hero ||= DayHero.pick(facts[:items], as_of: narration_date(facts))
      lore = enrichment_for(facts)
      sources = sources_from(lore)
      # available? (not just !disabled?): a station with no LLM configured skips the model
      # attempt entirely and takes the rich facts fallback — no doomed Bedrock call to rescue.
      # narratable? guards the model too: a day with zero detections has nothing to narrate, and
      # since the data can't tell a genuinely quiet day from a mic that was down, any prose would
      # assert a silence we can't vouch for. Fall to the bare template so the Journal and letter
      # speak from frozen coverage instead ("offline this day" vs "a quiet day").
      if narratable?(facts) && model && Bedrock.available? && (bullets = generate(facts, lore, hero))
        return { bullets: bullets, source: 'llm', sources: sources }
      end

      bullets, source = fallback(facts, lore)
      { bullets: bullets, source: source, sources: sources }
    end

    # Serialise the facts object + stored bird-lore into the user message. Public so a
    # spec (or a human) can eyeball exactly what the model is asked. `lore` is the shape
    # returned by enrichment_for: an array of { common_name:, irish_name:, blocks: }.
    def user_message(facts, lore = [], hero = nil)
      lines = ["Date: #{facts[:date]}. #{facts[:species_today]} species, " \
               "#{facts[:detections_today]} detections today."]
      lines << length_directive(facts)
      if (loudest = facts[:items].max_by { |i| i[:call_count] })
        lines << "Most detected today by count: #{loudest[:common_name]} (#{loudest[:call_count]})."
      end
      lines << 'Items (name, Irish, count, importance, flags) — IMPORTANCE order, not count order:'
      facts[:items].first(MAX_ITEMS).each { |item| lines << item_line(item) }
      lines << "Activity: #{activity_phrase(facts[:activity_note])}." if facts[:activity_note]
      lines << listening_line(facts[:listening])
      lead = lead_line(hero, facts)
      lines << lead if lead
      lines.concat(lore_lines(lore))
      lines.compact.join("\n")
    end

    private

    # A day is narratable only if something was actually detected. With zero detections there is
    # nothing to say AND no way to know whether the station was quiet or offline, so we never let
    # the model (or the facts fallback) speak — the template + frozen coverage carry the honest line.
    def narratable?(facts)
      facts[:detections_today].to_i.positive?
    end

    # Bilingual bullets { en:, ga: } or nil. English is generated from the facts + the stored
    # bird-lore; the second language (ga) is a translation of that English — but only when the
    # station offers a second language. A single-language station never translates and just
    # mirrors English into the ga slot, so no consumer has to special-case it.
    def generate(facts, lore = [], hero = nil)
      message = user_message(facts, lore, hero)
      message = "#{message}\n\n#{COMPLETED_DAY_NOTE}" if completed_day?(facts)
      en = attempt(format(Prompts.get('day_note.system'), where: station_context), message)
      return nil unless en && supported?(en, facts)

      { en: en, ga: second_language_bullets(en, facts) }
    end

    # The second-language rendering of the approved English bullets — a translation (not a
    # second free write) so the two can't disagree on the facts — falling back to the
    # deterministic template. Only engaged for a multilingual station; else it mirrors English.
    def second_language_bullets(en, facts)
      return en unless Station.multilingual?

      ga = attempt(Prompts.get('day_note.translate'), en.map { |b| "- #{b}" }.join("\n"))
      ga && ga.size == en.size ? ga : DailyFacts.template_bullets(facts)[:ga]
    end

    # Source the day's NOTABLE birds NOW if they lack a bundle — an arrival or a rarity is the
    # highest-priority thing to have real, cited lore for. Cached + durable → a one-time cost
    # per new bird. Capped and best-effort: a failure just leaves that bird un-enriched.
    def ensure_notable_enriched(facts)
      return if Bedrock.disabled?

      due = Array(facts[:notable_today]).
            reject { |i| EnrichmentBundle.current(i[:sci_name])&.block_objects&.any? }.
            first(ENRICH_ON_REFRESH)
      due.each do |item|
        Enrichment::Builder.build_one(date: Date.parse(facts[:date].to_s), sci_name: item[:sci_name],
                                      common_name: item[:common_name], irish_name: item[:irish_name])
      rescue StandardError => e
        Rails.logger.warn("DayNarrator: enrich #{item[:sci_name]} failed (#{e.class}: #{e.message})")
      end
    end

    # The distinct citations behind the material fed to the note — { host:, url: } pairs.
    def sources_from(lore)
      Array(lore).flat_map { |bird| Array(bird[:blocks]) }.
        flat_map { |block| Array(block[:sources]) }.
        filter_map { |s| { host: s[:host], url: s[:url] } if s[:url].present? }.uniq
    end

    # The stored facts & folklore for the day's most prominent species — a pure DB read of
    # the latest EnrichmentBundle per species (durable across days), so nothing is fetched.
    def enrichment_for(facts)
      items = Array(facts[:items])
      prominent = (items.first(LORE_SPECIES) + [items.max_by { |i| i[:call_count] }]).
                  compact.uniq { |i| i[:sci_name] }
      bundles = EnrichmentBundle.current_for(prominent.pluck(:sci_name)).index_by(&:sci_name)
      prominent.filter_map do |item|
        display = bundles[item[:sci_name]]&.to_display
        next unless display

        # Folklore is deliberately withheld from the model: sourced folklore (dúchas and
        # friends) renders as a SET-APART, attributed quote on the Journal — like the
        # curated poems — never paraphrased into the narration's prose.
        blocks = display[:blocks].reject { |b| b[:type] == 'folklore' }
        next if blocks.empty?

        { common_name: item[:common_name], irish_name: item[:irish_name], blocks: blocks }
      end
    end

    # The no-LLM fallback — [bullets, source]. Deliberately BIRD CHARACTER, not a recap: the
    # day's genuine news (a named all-time/year first) then a striking fact or folklore about
    # each prominent enriched bird, verbatim from the vetted bundles. The counts / "most heard"
    # / activity lines are left OUT. Shown as 'facts'; falls to the bare 'template' (hidden)
    # only when there is genuinely nothing to say.
    def fallback(facts, lore)
      cap = target_bullets(facts).max
      news = news_bullets(facts)
      character = character_bullets(lore, cap)
      en = (news[:en] + character[:en]).first(cap)
      ga = (news[:ga] + character[:ga]).first(cap)
      return [{ en: en, ga: ga }, 'facts'] if en.any?

      [DailyFacts.template_bullets(facts), 'template']
    end

    # How many bullets today earns — brief when nothing is notable, fuller as the notable birds
    # (DailyFacts' importance ≥ NOTABLE_IMPORTANCE) stack up, so the entry breathes with the day.
    def target_bullets(facts)
      case Array(facts[:notable_today]).size
      when 0 then 1..2
      when 1 then 2..3
      when 2 then 3..4
      else 4..MAX_BULLETS
      end
    end

    # The instruction the model reads for length + shape — scaled to the day's notable count.
    def length_directive(facts)
      range = target_bullets(facts)
      notable = Array(facts[:notable_today]).size
      shape = if notable >= 2
                "A full day — #{notable} notable birds. Give the LEAD bird its own bullet, then a " \
                  'striking, sourced detail on each other notable bird; routine birds are light texture.'
              elsif notable == 1
                'One notable bird — feature it; the routine birds are light texture around it.'
              else
                'A quiet day — keep it brief; a bullet or two on the most characterful bird is enough.'
              end
      "LENGTH: write #{range.min} to #{range.max} bullets. #{shape}"
    end

    # The LEAD line: open the entry with the day's hero, phrased from its flag. Falls back to the
    # DailyFacts spotlight when no hero is supplied (a direct user_message call), so specs and any
    # legacy caller keep the old advisory line.
    def lead_line(hero, facts)
      return facts[:spotlight] && spotlight_line(facts[:spotlight]) if hero.nil?

      irish = hero[:irish_name].present? ? " (#{hero[:irish_name]})" : ''
      context = HERO_CONTEXT.find { |flag, _| Array(hero[:flags]).include?(flag) }&.last
      tail = context ? " — #{context}" : ''
      "LEAD (open the entry with this bird): #{hero[:common_name]}#{irish}#{tail}."
    end

    def narration_date(facts)
      Date.parse(facts[:date].to_s)
    rescue ArgumentError, TypeError
      Date.current
    end

    # Today's genuine news as bilingual bullets — an all-time or year first, named.
    def news_bullets(facts)
      arrivals = Array(facts[:items]).select { |i| Array(i[:flags]).intersect?(NEWS_FLAGS) }.first(2)
      { en: arrivals.map { |i| news_line(i, :en) }, ga: arrivals.map { |i| news_line(i, :ga) } }
    end

    def news_line(item, lang)
      kind = Array(item[:flags]).include?('year_first') ? :year_first : :all_time_first
      name = lang == :ga ? item[:irish_name].presence || item[:common_name] : item[:common_name]
      "#{NEWS_LABEL[lang][kind]}: #{name}."
    end

    # A genuinely interesting thing about the day's birds — a behaviour/habit fact or a piece
    # of folklore — scanning ALL the prominent enriched birds and taking the best three.
    def character_bullets(lore, limit = 3)
      picked = Array(lore).filter_map { |bird| interesting_block(bird[:blocks]) }.first(limit)
      { en: picked.pluck(:text), ga: picked.map { |b| b[:text_ga].presence || b[:text] } }
    end

    def interesting_block(blocks)
      vivid_fact(blocks) || folklore(blocks)
    end

    def vivid_fact(blocks)
      blocks.find { |b| b[:type] == 'fact' && !b[:text].to_s.match?(DULL_FACT) }
    end

    def folklore(blocks)
      blocks.find { |b| b[:type] == 'folklore' }
    end

    # Render the stored lore into the prompt: each prominent bird, then its typed blocks.
    def lore_lines(lore)
      return [] if lore.blank?

      lines = ['About the birds (the ONLY characterising detail you may state — weave one ' \
               'or two striking things in):']
      lore.each do |bird|
        irish = bird[:irish_name].present? ? " (#{bird[:irish_name]})" : ''
        lines << "#{bird[:common_name]}#{irish}:"
        bird[:blocks].each { |block| lines << "  - [#{block[:type]}] #{block[:text]}" }
      end
      lines
    end

    # A last-ditch factuality gate: if nothing today is a first, a summary that still calls
    # something a first is wrong — reject it, take the fallback.
    def supported?(bullets, facts)
      return false if counted_individuals?(bullets, facts)
      return true if facts[:items].any? { |i| Array(i[:flags]).intersect?(ARRIVAL_FLAGS) }

      bullets.none? { |b| b.match?(NOVELTY) && !b.match?(NEGATION) }
    end

    # The other half of "a count is detections, not birds": "137 house sparrows" claims 137
    # creatures as surely as "137 birds" does, and only the day's own species names can catch
    # it. Number FIRST, name second — "the herring gull led the day at 203" is the correct
    # shape and is left alone.
    def counted_individuals?(bullets, facts)
      names = Array(facts[:items]).filter_map { |i| i[:common_name].presence }.uniq
      return false if names.empty?

      plural = /\b\d+\s+(?:#{names.map { |n| Regexp.escape(n) }.join('|')})s\b/i
      offender = bullets.find { |b| b.match?(plural) }
      Rails.logger.warn("DayNarrator: rejected — counted individuals, not detections: #{offender}") if offender
      offender.present?
    end

    # One model round-trip → validated bullets, or nil (unreachable model, or output that
    # breaks a house rule). Isolated so an Irish-translation failure never sinks the English.
    def attempt(system, user)
      bullets = parse(Bedrock.converse(system: system, user: user,
                                       model_id: NARRATOR_MODEL.call, max_tokens: NARRATOR_TOKENS))
      valid?(bullets) ? bullets : nil
    rescue StandardError => e
      Rails.logger.warn("DayNarrator: LLM call failed (#{e.class}: #{e.message})")
      nil
    end

    # Model text → bullet strings. Tolerates "- ", "* " or "• " markers and drops preamble.
    def parse(raw)
      raw.to_s.lines.filter_map do |line|
        text = line.strip
        next unless text.match?(/\A[-*•]\s+/)

        text.sub(/\A[-*•]\s+/, '').strip
      end
    end

    # 1–MAX_BULLETS non-empty bullets, none shouting (an exclamation mark is a house-rule
    # violation), and none counting BIRDS where the facts only ever counted detections. The
    # prompt's LENGTH line sets the target within this; validation just guards the ceiling and
    # the house rules. A rejected attempt falls back to the deterministic template, which
    # states the counts correctly — a plain true line beats a warm false one.
    def valid?(bullets)
      return false unless bullets.size.between?(1, MAX_BULLETS) && bullets.all?(&:present?)
      return false if bullets.any? { |b| b.include?('!') }

      offender = bullets.find { |b| b.match?(COUNTED_BIRDS) }
      Rails.logger.warn("DayNarrator: rejected — counted birds, not detections: #{offender}") if offender
      offender.nil?
    end

    def item_line(item)
      irish = item[:irish_name].present? ? " (#{item[:irish_name]})" : ''
      flags = item[:flags].join(', ')
      line = "- #{item[:common_name]}#{irish}, #{item[:call_count]}, importance #{item[:importance]}, [#{flags}]"
      line += "\n  Background (#{item[:common_name]}): #{item[:blurb]}" if item[:blurb].present?
      line
    end

    def spotlight_line(spotlight)
      line = "Spotlight: #{spotlight[:common_name]} — #{spotlight[:rarity_context]}."
      line += " Background: #{spotlight[:blurb]}" if spotlight[:blurb].present?
      line
    end

    # The coverage stat, stated whenever the recorder missed part of the day — every count in
    # this prompt has to be read against it. Without it the model sees a short count and calls
    # the day quiet, which is the one thing it must not do: the birds were not quieter, the
    # station was not listening. DailyFacts already withholds the pace verdict when coverage is
    # poor; this tells the narration what to say in its place, so a gap reads as a gap.
    def listening_line(cover)
      return nil unless cover

      live = cover[:hours_live].to_i
      elapsed = cover[:hours_elapsed].to_i
      return nil if elapsed.zero? || live >= elapsed

      "Recorder coverage: listening for #{live} of #{elapsed} hours - the mic was DOWN for " \
        "#{elapsed - live}. Every count here covers only the listening time. Do NOT call the day " \
        'quiet, slow, sparse or below average: that is missing coverage, not bird behaviour. ' \
        'If you mention volume at all, say the station was offline for part of the day.'
    end

    def activity_phrase(note)
      ACTIVITY_PHRASES.fetch(note.to_s, note.to_s.tr('_', ' '))
    end

    # A day is "completed" (a Journal entry) when its date is before today — the front page's
    # in-progress day is not. Drives the past-tense framing.
    def completed_day?(facts)
      date = facts[:date].to_s
      date.present? && date < Date.current.iso8601
    end

    # The station's location for the prompt, from config/API (Station) — never a literal.
    def station_context
      Station.region.present? ? " in #{Station.region}" : ''
    end
  end
end
