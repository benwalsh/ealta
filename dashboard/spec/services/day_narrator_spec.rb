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
                blocks: [{ type: 'folklore', text: 'Old lore tied the sparrow to the hearth.' }] }]
      msg = described_class.user_message(facts, lore)
      expect(msg).to include('About the birds')
      expect(msg).to include('House Sparrow (Gealbhan binne):')
      expect(msg).to include('[folklore] Old lore tied the sparrow to the hearth.')
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
end
