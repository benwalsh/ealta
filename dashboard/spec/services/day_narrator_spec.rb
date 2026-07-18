require 'rails_helper'

RSpec.describe DayNarrator do
  # A fixed facts object so these tests exercise only the narration layer (prompting,
  # enrichment lookup, fallback) — never the DailyFacts engine.
  let(:facts) do
    {
      date: '2026-07-03', species_today: 3, detections_today: 42,
      items: [
        { sci_name: 'Tringa nebularia', common_name: 'Common Greenshank', irish_name: 'Laidhrín glas',
          call_count: 1, importance: 100, flags: %w[all_time_first] },
        { sci_name: 'Passer domesticus', common_name: 'House Sparrow', irish_name: 'Gealbhan binne',
          call_count: 30, importance: 5, flags: %w[routine most_common] }
      ],
      spotlight: { common_name: 'Common Greenshank', irish_name: 'Laidhrín glas',
                   rarity_context: 'first record at the station', blurb: 'A wading bird.' },
      activity_note: 'quieter_than_typical'
    }
  end

  describe '.user_message' do
    it 'serialises the facts object into the prompt the model sees' do
      msg = described_class.user_message(facts)
      expect(msg).to include('3 species, 42 detections today')
      expect(msg).to include('Common Greenshank (Laidhrín glas), 1, importance 100, [all_time_first]')
      expect(msg).to include('Activity: quieter than typical.')
      expect(msg).to include('Spotlight: Common Greenshank — first record at the station.')
      expect(msg).to include('Background: A wading bird.')
    end

    it 'appends the stored bird-lore as an "About the birds" section' do
      lore = [{ common_name: 'House Sparrow', irish_name: 'Gealbhan binne',
                blocks: [{ type: 'fact', text: 'Nests under the eaves of houses.' }] }]
      msg = described_class.user_message(facts, lore)
      expect(msg).to include('About the birds')
      expect(msg).to include('House Sparrow (Gealbhan binne):')
      expect(msg).to include('[fact] Nests under the eaves of houses.')
    end

    it 'scales the length directive with the day\'s notable count' do
      quiet = facts.merge(notable_today: [])
      full  = facts.merge(notable_today: [{ sci_name: 'a' }, { sci_name: 'b' }, { sci_name: 'c' }])
      expect(described_class.user_message(quiet)).to include('LENGTH: write 1 to 2 bullets')
      expect(described_class.user_message(full)).to include('LENGTH: write 4 to 5 bullets').
        and include('3 notable birds')
    end

    it 'opens on the supplied day hero as the LEAD, phrased from its flag' do
      hero = facts[:items].first # the greenshank, an all-time first
      msg = described_class.user_message(facts, [], hero)
      expect(msg).to include(
        'LEAD (open the entry with this bird): Common Greenshank (Laidhrín glas) — a first for the station.'
      )
    end
  end

  # The station records SOUNDS. It cannot count individuals — one bird calling all morning is
  # many detections — so "two birds logged" is false, and it is the easiest falsehood for a
  # narrator to reach for. The prompt forbids it; these are the guards that don't rely on the
  # model obeying prose. A rejected attempt falls back to the deterministic template, which
  # states the counts correctly.
  describe 'refusing to count birds instead of detections' do
    it 'rejects a bullet that turns detections into a number of birds' do
      ['two birds logged', 'a dozen birds about the feeders', 'three garden birds were heard'].each do |bullet|
        expect(described_class.send(:valid?, [bullet])).to be(false), "expected #{bullet.inspect} rejected"
      end
    end

    it 'rejects a bullet that counts individuals of a named species' do
      expect(described_class.send(:counted_individuals?, ['30 house sparrows about the hedge'], facts)).to be(true)
    end

    it 'leaves the correct shapes alone — a count of times, not of creatures' do
      ['the house sparrow was heard 30 times', 'the greenshank led the day at 42 detections',
       'heard twice, both before dawn', 'the birds were quiet all afternoon'].each do |bullet|
        expect(described_class.send(:valid?, [bullet])).to be(true), "expected #{bullet.inspect} allowed"
        expect(described_class.send(:counted_individuals?, [bullet], facts)).to be(false)
      end
    end

    # The rule has to be in the prompt too — the guards are a backstop, not the teaching.
    it 'tells the narrator the rule in the prompt itself' do
      expect(Prompts.get('day_note.system')).to include('NOT HOW MANY BIRDS')
    end
  end

  describe '.enrichment_for' do
    it 'pulls the latest stored bundle for the day\'s prominent species (incl. the loudest)' do
      EnrichmentBundle.create!(
        sci_name: 'Passer domesticus', date: '2026-07-01',
        common_name: 'House Sparrow', irish_name: 'Gealbhan binne',
        blocks: [{ 'type' => 'fact', 'id' => 'chirpy', 'text' => 'Chirps from the eaves.',
                   'text_ga' => nil, 'gated' => false,
                   'sources' => [{ 'host' => 'en.wikipedia.org', 'url' => 'https://en.wikipedia.org/wiki/x' }] }]
      )
      lore = described_class.send(:enrichment_for, facts)
      sparrow = lore.find { |b| b[:common_name] == 'House Sparrow' }
      expect(sparrow[:blocks].first[:text]).to eq('Chirps from the eaves.')
    end

    it 'is empty when no prominent species has a stored bundle' do
      expect(described_class.send(:enrichment_for, facts)).to eq([])
    end

    it 'withholds folklore from the model material — it renders as a set-apart quote instead' do
      EnrichmentBundle.create!(
        sci_name: 'Passer domesticus', date: '2026-07-01',
        blocks: [{ 'type' => 'folklore', 'id' => 'hearth', 'gated' => true,
                   'text' => 'Old lore tied the sparrow to the hearth.',
                   'sources' => [{ 'host' => 'duchas.ie', 'url' => 'https://duchas.ie/story/2' }] }]
      )
      lore = described_class.send(:enrichment_for, facts)
      expect(lore.find { |b| b[:common_name] == 'House Sparrow' }).to be_nil
    end
  end

  describe '.narrate' do
    it 'returns the rich fallback (news, no recap) with model: false — never touching the model' do
      expect(Bedrock).not_to receive(:converse)
      result = described_class.narrate(facts, model: false)
      expect(result[:source]).to eq('facts') # the fixture carries an all-time first
      expect(result[:bullets][:en]).to include('New for the station: Common Greenshank.')
      expect(result[:bullets][:en].join).not_to match(/detections logged today|Most heard/)
    end

    it 'narrates with the model when one is available' do
      allow(Bedrock).to receive_messages(
        disabled?: false, available?: true,
        converse:  "- A Common Greenshank (Laidhrín glas) was heard for the first time.\n" \
                   '- The usual sparrows made up the rest of a quiet day.'
      )
      result = described_class.narrate(facts)
      expect(result[:source]).to eq('llm')
      expect(result[:bullets][:en].size).to eq(2)
      expect(result[:bullets][:ga].size).to eq(2) # the Irish translation pass
    end

    it 'never narrates a zero-detection day — the model is not asked to describe silence' do
      # We can't tell a genuinely quiet day from a mic that was down, so an empty day must fall to
      # the bare template (the Journal/letter speak from coverage), never to invented prose.
      empty = facts.merge(species_today: 0, detections_today: 0, items: [], notable_today: [])
      allow(Bedrock).to receive_messages(disabled?: false, available?: true)
      expect(Bedrock).not_to receive(:converse)
      result = described_class.narrate(empty)
      expect(result[:source]).to eq('template')
    end

    it 'accepts a fuller entry (up to five bullets) on a busy day' do
      five = (1..5).map { |i| "- A notable bird, number #{i}." }.join("\n")
      allow(Bedrock).to receive_messages(disabled?: false, available?: true, converse: five)
      result = described_class.narrate(facts.merge(notable_today: facts[:items]))
      expect(result[:source]).to eq('llm')
      expect(result[:bullets][:en].size).to eq(5)
    end
  end

  # A completed (past) day is the Journal's — it must read in retrospect; only the front page's
  # in-progress day says "today". The fixture's date (2026-07-03) is before the test's today.
  describe 'completed-day framing' do
    # The generic stub covers the Irish translation pass (whose prompt never carries the note).
    before do
      allow(Bedrock).to receive_messages(disabled?: false, available?: true,
                                         converse: "- A quiet day.\n- The usual sparrows.")
    end

    it 'instructs the past tense when the date is a completed day' do
      expect(Bedrock).to receive(:converse).
        with(hash_including(user: a_string_including('PAST TENSE'))).
        and_return("- A quiet day.\n- The usual sparrows.")
      described_class.narrate(facts) # the fixture's 2026-07-03 is before the real today
    end

    it 'keeps the "today" framing for the current day' do
      expect(Bedrock).not_to receive(:converse).with(hash_including(user: a_string_including('PAST TENSE')))
      travel_to(Time.zone.local(2026, 7, 3, 15)) { described_class.narrate(facts) }
    end
  end

  describe '.listening_line' do
    it 'tells the model the mic was down, and forbids calling the day quiet' do
      line = described_class.send(:listening_line, { hours_live: 7, hours_elapsed: 18 })
      expect(line).to include('7 of 18 hours')
      expect(line).to match(/do NOT call the day/i)
    end

    it 'says nothing when the recorder was up the whole time' do
      expect(described_class.send(:listening_line, { hours_live: 18, hours_elapsed: 18 })).to be_nil
      expect(described_class.send(:listening_line, nil)).to be_nil
    end
  end
end
