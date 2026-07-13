# The LLM system prompts. The ENGINE owns the neutral defaults (config/prompts/*.md) — they
# are mechanism prose, only ever read when a station has opted into the LLM (station.yml
# `llm:`), which is why a profile ships no prompts at all by default. A station that wants a
# different VOICE overrides one by placing prompts/<name>.md in its profile.
#
# Only the SYSTEM PROSE lives in these files; Ruby still owns every count, ranking, gate and
# citation (DayNarrator, Enrichment::Builder), so "Ruby computes, the model narrates" is
# unchanged — the prompt text is simply data.
#
#   Prompts.get('day_note.system')
#     → stations/<profile>/prompts/day_note.system.md   (a station retuning its voice)
#     → dashboard/config/prompts/day_note.system.md     (the engine's neutral default)
#
# A missing core prompt raises rather than silently sending an empty system prompt.
class Prompts
  DEFAULTS_DIR = Rails.root.join('config/prompts')

  class << self
    def get(name)
      StationProfile.read("prompts/#{name}.md") || default(name) ||
        raise("Prompts: no prompt file for #{name.inspect} (checked the profile and config/prompts)")
    end

    private

    def default(name)
      path = DEFAULTS_DIR.join("#{name}.md")
      path.file? ? path.read : nil
    end
  end
end
