require 'rails_helper'
require 'tmpdir'

RSpec.describe TodaySummary do
  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:file) { dir.join('today_summary.json') }

  # A fixed facts object so these tests exercise only the summary layer (prompting,
  # caching, validation, fallback) — never the DailyFacts engine or the database.
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

  before do
    stub_const('TodaySummary::STORE', file)
    allow(DailyFacts).to receive(:for).and_return(facts)
  end

  after { FileUtils.remove_entry(dir) if dir.exist? }

  describe '.current' do
    it 'synthesises from facts when there is no cache (the day\'s news, not a tally)' do
      result = described_class.current(facts: facts)
      expect(result[:source]).to eq('facts') # the fixture carries an all-time first
      expect(result[:bullets][:en]).to include('New for the station: Common Greenshank.')
      expect(result[:bullets][:en].join).not_to include('detections logged today')
    end

    it 'discards a cache left over from a previous day (so "today" is never stale)' do
      allow(Bedrock).to receive(:disabled?).and_return(true)
      travel_to(Time.zone.local(2026, 7, 3, 12)) { described_class.refresh } # cache dated 2026-07-03
      newer = facts.merge(date: '2026-07-06', species_today: 9)
      result = described_class.current(facts: newer)
      expect(result[:facts_date]).to eq('2026-07-06') # recomputed for today, not the 07-03 cache
    end
  end

  describe '.refresh_if_stale' do
    before { allow(Bedrock).to receive(:disabled?).and_return(true) } # template path — no network

    it 'refreshes when there is no cache yet' do
      travel_to(Time.zone.local(2026, 7, 3, 12)) do
        expect { described_class.refresh_if_stale }.to change(file, :exist?).from(false).to(true)
      end
    end

    it 'skips the refresh when the cache is fresh (same day, recent)' do
      travel_to(Time.zone.local(2026, 7, 3, 12)) do
        described_class.refresh
        expect(described_class).not_to receive(:refresh)
        described_class.refresh_if_stale
      end
    end

    it 'refreshes when the cache is from an earlier day' do
      travel_to(Time.zone.local(2026, 7, 3, 12)) { described_class.refresh } # cache dated 2026-07-03
      travel_to(Time.zone.local(2026, 7, 4, 9)) do
        expect(described_class).to receive(:refresh)
        described_class.refresh_if_stale
      end
    end
  end

  describe '.refresh' do
    context 'when the LLM is disabled' do
      before { allow(Bedrock).to receive(:disabled?).and_return(true) }

      it 'writes the bare template (hidden) only when there is no news and nothing enriched' do
        routine = facts.merge(items: [{ sci_name: 'Passer domesticus', common_name: 'House Sparrow',
                                        irish_name: 'Gealbhan binne', call_count: 30, importance: 5,
                                        flags: %w[routine most_common] }])
        allow(DailyFacts).to receive(:for).and_return(routine)
        result = described_class.refresh
        expect(result[:source]).to eq('template')
      end

      it 'writes bird CHARACTER — news + a fact — not the "N species / most heard" recap' do
        EnrichmentBundle.create!(
          sci_name: 'Passer domesticus', date: '2026-07-01',
          common_name: 'House Sparrow', irish_name: 'Gealbhan binne',
          blocks: [{ 'type' => 'fact', 'id' => 'roost', 'text' => 'House sparrows roost communally in winter.',
                     'text_ga' => 'Fanann gealbhain le chéile sa gheimhreadh.', 'gated' => false,
                     'sources' => [{ 'host' => 'en.wikipedia.org', 'url' => 'https://en.wikipedia.org/wiki/x' }] }]
        )
        result = described_class.refresh
        expect(result[:source]).to eq('facts') # shown, not hidden
        # the genuine news (the all-time first), then the stored fact
        expect(result[:bullets][:en]).to include('New for the station: Common Greenshank.')
        expect(result[:bullets][:en]).to include('House sparrows roost communally in winter.')
        expect(result[:bullets][:ga]).to include('Fanann gealbhain le chéile sa gheimhreadh.')
        # the dumbed-down recap lines are gone
        expect(result[:bullets][:en].join).not_to match(/detections logged today|Most heard/)
      end
    end

    context 'when the LLM returns good bullets' do
      before do
        allow(Bedrock).to receive_messages(
          disabled?: false, available?: true,
          converse:  "- A Common Greenshank (Laidhrín glas) was heard for the first time.\n" \
                     '- The usual sparrows made up the rest of a quiet day.'
        )
      end

      it 'caches the narrated bilingual summary and reads it back' do
        result = described_class.refresh
        expect(result[:source]).to eq('llm')
        expect(result[:bullets][:en].size).to eq(2)
        expect(result[:bullets][:ga].size).to eq(2) # the Irish translation pass
        expect(described_class.current[:bullets][:en].first).to include('Greenshank')
      end
    end

    context 'when the model output breaks a house rule' do
      before do
        allow(Bedrock).to receive_messages(disabled?: false, available?: true,
                                           converse:  '- A busy, thriving day for ealta!')
      end

      it 'rejects it and falls through to the deterministic fallback (never the model line)' do
        result = described_class.refresh
        expect(result[:source]).to eq('facts') # rejected the LLM; the fixture's first becomes news
        expect(result[:bullets][:en].join).not_to include('thriving')
      end
    end

    context 'when the model invents a "first" on a day with no arrivals' do
      let(:routine_facts) do
        facts.merge(items: [{ common_name: 'Graylag Goose', irish_name: 'Gé ghlas',
                              call_count: 8, importance: 5, flags: %w[routine] }])
      end

      before do
        allow(DailyFacts).to receive(:for).and_return(routine_facts)
        allow(Bedrock).to receive_messages(
          disabled?: false, available?: true,
          converse:  "- First detection today of the Graylag Goose.\n- A quiet day otherwise."
        )
      end

      it 'rejects the untrue novelty claim and falls through to the template' do
        # Nothing is flagged all_time_first/year_first, so "first" cannot be true.
        expect(described_class.refresh[:source]).to eq('template')
        expect(described_class.current[:bullets][:en].join).not_to match(/first/i)
      end
    end

    context 'when the model correctly reports NO firsts on a quiet day' do
      let(:routine_facts) do
        facts.merge(items: [{ common_name: 'House Sparrow', irish_name: 'Gealbhan binne',
                              call_count: 30, importance: 5, flags: %w[routine most_common] }])
      end

      before do
        allow(DailyFacts).to receive(:for).and_return(routine_facts)
        allow(Bedrock).to receive_messages(
          disabled?: false, available?: true,
          converse:  "- A quiet day, the usual sparrows.\n- No new arrivals or firsts were detected today."
        )
      end

      it 'keeps it — a negated mention of firsts is a true statement, not a false claim' do
        expect(described_class.refresh[:source]).to eq('llm')
      end
    end

    context 'when generation fails but a good summary is already cached' do
      before { allow(Bedrock).to receive_messages(disabled?: false, available?: true) }

      it 'keeps the last-good cache rather than overwriting it' do
        allow(Bedrock).to receive(:converse).and_return("- First good line.\n- Second good line.")
        described_class.refresh

        allow(Bedrock).to receive(:converse).and_raise(Seahorse::Client::NetworkingError.new(StandardError.new('down')))
        result = described_class.refresh

        expect(result[:source]).to eq('llm')
        expect(result[:bullets][:en]).to eq(['First good line.', 'Second good line.'])
      end
    end
  end
end
