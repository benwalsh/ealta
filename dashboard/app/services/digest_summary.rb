# Narrates a DigestFacts object into a short personal note — the warm counterpart to
# the mechanical digest list. Same discipline as TodaySummary: Ruby has computed every
# fact; the model only phrases them, under absolute factual rules. Returns the note as
# paragraph lines, or nil on any failure/violation so the caller falls back to the
# deterministic email. A per-user one-shot at send time — no cache. Warmth degrades to
# correctness; it never blocks a send and never invents.
class DigestSummary
  class << self
    # The note as an array of paragraph lines, or nil to fall back to the list email.
    def for(facts)
      return nil unless Bedrock.available? # no LLM configured → the deterministic list email

      raw = Bedrock.converse(system: format(Prompts.get('digest_summary.system'), where: station_context),
                             user:   user_message(facts))
      note = clean(raw)
      valid?(note) ? note : nil
    rescue StandardError => e
      Rails.logger.warn("DigestSummary: generation failed (#{e.class}: #{e.message})")
      nil
    end

    # Public so a spec (or a human) can eyeball exactly what the model is asked.
    def user_message(facts)
      lines = ["Date: #{facts.date}."]
      lines << follows_line(facts.follows)
      lines << alerts_line(facts.alerts) if facts.alerts.any?
      lines << roundup_line(facts.roundup) if facts.roundup
      lines.join("\n")
    end

    private

    def follows_line(follows)
      return 'Birds the reader follows heard today: none.' if follows.empty?

      list = follows.map { |f| "#{f[:en]} (#{f[:ga]}) x#{f[:count]}" }.join('; ')
      "Birds the reader follows heard today: #{list}."
    end

    def alerts_line(alerts)
      list = alerts.map { |a| "#{a[:kind].tr('_', ' ')}: #{a[:en]}" }.join('; ')
      "Flagged arrivals they subscribe to: #{list}."
    end

    def roundup_line(roundup)
      note = roundup[:activity_note] ? ", #{roundup[:activity_note].tr('_', ' ')}" : ''
      "The station day overall: #{roundup[:species_today]} species, #{roundup[:detections_today]} detections#{note}."
    end

    def clean(raw)
      raw.to_s.strip.split(/\n{2,}/).map { |para| para.tr("\n", ' ').squeeze(' ').strip }.reject(&:empty?)
    end

    # Non-empty, not shouting, not a runaway generation.
    def valid?(note)
      note.any? && note.none? { |para| para.include?('!') } && note.join(' ').length.between?(20, 900)
    end

    def station_context
      Station.region.present? ? " in #{Station.region}" : ''
    end
  end
end
