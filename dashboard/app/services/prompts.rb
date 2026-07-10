# The LLM system prompts live as files in the station profile (prompts/*.md), not as heredoc
# constants in the code — so an instance can retune its voice, and the open-source core ships a
# neutral default, without a code change. This moves only the SYSTEM PROSE out; Ruby still owns
# every count, ranking, gate and citation (DayNarrator, Enrichment::Builder), so "Ruby computes,
# the model narrates" is unchanged — the prompt text is simply data now.
#
#   Prompts.get('day_note.system')  # → stations/<profile>/prompts/day_note.system.md
#
# Resolution and caching are StationProfile's (profile → example); a missing core prompt raises
# rather than silently sending an empty system prompt.
class Prompts
  class << self
    def get(name)
      StationProfile.read("prompts/#{name}.md") ||
        raise("Prompts: no prompt file for #{name.inspect} (checked the profile and stations/example)")
    end
  end
end
