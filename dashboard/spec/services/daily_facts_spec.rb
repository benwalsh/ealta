require 'rails_helper'

RSpec.describe DailyFacts do
  # A fixed "now" so date arithmetic (arrival windows, station age) is deterministic.
  let(:now) { Time.zone.local(2026, 7, 3, 10, 0, 0) }
  let(:today) { now.to_date }

  # rubocop:disable RSpecRails/TravelAround -- the conditional skip needs a block form
  around { |ex| ex.metadata[:no_travel] ? ex.run : travel_to(now) { ex.run } }
  # rubocop:enable RSpecRails/TravelAround

  # Give the station a year of history so all-time-firsts score their full weight
  # (the young-station guard damps them otherwise).
  def age_the_station!
    create(:detection, Sci_Name: 'Pica pica', Com_Name: 'Eurasian Magpie',
                       Date: (today - 400), Time: now, Confidence: 0.9)
  end

  describe 'the two kinds of first' do
    it 'flags a never-before-heard species as all_time_first, importance 100' do
      age_the_station!
      create(:detection, Sci_Name: 'Tringa nebularia', Com_Name: 'Common Greenshank',
                         Date: today, Time: now, Confidence: 0.9)

      facts = described_class.for(now: now)
      item = facts[:items].find { |i| i[:sci_name] == 'Tringa nebularia' }

      expect(item[:flags]).to include('all_time_first')
      expect(item[:importance]).to eq(100)
    end

    it 'flags a species absent for the arrival window as year_first, importance 80' do
      create(:detection, Sci_Name: 'Apus apus', Com_Name: 'Common Swift',
                         Date: (today - 200), Time: now, Confidence: 0.9)
      create(:detection, Sci_Name: 'Apus apus', Com_Name: 'Common Swift',
                         Date: today, Time: now, Confidence: 0.9)

      facts = described_class.for(now: now)
      item = facts[:items].find { |i| i[:sci_name] == 'Apus apus' }

      expect(item[:flags]).to include('year_first')
      expect(item[:flags]).not_to include('all_time_first')
      expect(item[:importance]).to eq(80)
    end

    it 'does not flag a resident heard daily as year_first (no New Year avalanche)', :no_travel do
      newyear = Time.zone.local(2026, 1, 1, 10, 0, 0)
      travel_to(newyear) do
        (0..40).each do |days_ago|
          create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                             Date: (newyear.to_date - days_ago), Time: newyear, Confidence: 0.9)
        end

        item = described_class.for(now: newyear)[:items].find { |i| i[:sci_name] == 'Erithacus rubecula' }
        expect(item[:flags]).not_to include('year_first')
        expect(item[:flags]).not_to include('all_time_first')
      end
    end
  end

  describe 'notable_today' do
    it 'never includes a routine species' do
      age_the_station!
      # A resident heard on many recent days: routine, importance 5.
      (0..20).each do |days_ago|
        create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
                           Date: (today - days_ago), Time: now, Confidence: 0.9)
      end

      facts = described_class.for(now: now)
      robin = facts[:items].find { |i| i[:sci_name] == 'Erithacus rubecula' }

      expect(robin[:importance]).to eq(5)
      expect(facts[:notable_today].pluck(:sci_name)).not_to include('Erithacus rubecula')
    end
  end

  describe 'spotlight' do
    it 'picks the single highest-importance item, all_time_first over year_first' do
      age_the_station!
      # A year-first (heard long ago, back today) …
      create(:detection, Sci_Name: 'Apus apus', Com_Name: 'Common Swift',
                         Date: (today - 200), Time: now, Confidence: 0.9)
      create(:detection, Sci_Name: 'Apus apus', Com_Name: 'Common Swift',
                         Date: today, Time: now, Confidence: 0.9)
      # … and an all-time-first, which must win the spotlight.
      create(:detection, Sci_Name: 'Tringa nebularia', Com_Name: 'Common Greenshank',
                         Date: today, Time: now, Confidence: 0.9)

      spotlight = described_class.for(now: now)[:spotlight]
      expect(spotlight[:common_name]).to eq('Common Greenshank')
      expect(spotlight[:rarity_context]).to eq('first record at the station')
      expect(spotlight).not_to have_key(:blurb)
    end

    it 'fetches the background blurb only when asked' do
      age_the_station!
      create(:detection, Sci_Name: 'Tringa nebularia', Com_Name: 'Common Greenshank',
                         Date: today, Time: now, Confidence: 0.9)
      # The top arrival is fetched both as an arrival (fed to the LLM) and as the
      # spotlight; SpeciesInfo caches, so the second call is a no-op.
      expect(SpeciesInfo).to receive(:english_for).
        with('Tringa nebularia', 'Common Greenshank').at_least(:once).and_return('A wading bird of estuaries.')

      spotlight = described_class.for(now: now, spotlight_blurb: true)[:spotlight]
      expect(spotlight[:blurb]).to eq('A wading bird of estuaries.')
    end
  end

  describe 'activity_curve_24h' do
    it 'buckets today\'s detections by the hour they were heard' do
      create(:detection, Date: today, Time: Time.zone.local(2026, 7, 3, 6, 15))
      create(:detection, Date: today, Time: Time.zone.local(2026, 7, 3, 6, 45))
      create(:detection, Date: today, Time: Time.zone.local(2026, 7, 3, 9, 5))

      curve = described_class.for(now: now)[:activity_curve_24h]
      expect(curve.size).to eq(24)
      expect(curve.find { |b| b[:hour] == 6 }[:count]).to eq(2)
      expect(curve.find { |b| b[:hour] == 9 }[:count]).to eq(1)
      expect(curve.find { |b| b[:hour] == 3 }[:count]).to eq(0)
    end
  end

  describe '.template_bullets' do
    it 'produces deterministic, always-correct bullets from a facts hash' do
      facts = {
        species_today: 3, detections_today: 42,
        items: [
          { common_name: 'Common Greenshank', flags: %w[all_time_first] },
          { common_name: 'Common Swift', flags: %w[year_first] },
          { common_name: 'House Sparrow', flags: %w[routine most_common] }
        ]
      }
      bullets = described_class.template_bullets(facts)
      expect(bullets[:en].first).to eq('3 species and 42 detections logged today.')
      expect(bullets[:en]).to include('New for the station: Common Greenshank.')
      expect(bullets[:en]).to include('First of the year: Common Swift.')
      expect(bullets[:en]).to include('Most heard: House Sparrow.')
      # Irish scaffolding is present too (names fall back to English where no Irish exists).
      expect(bullets[:ga].first).to eq('3 speiceas agus 42 brath logáilte inniu.')
    end
  end

  describe '.station_age_days' do
    it 'counts days since the first-ever detection' do
      create(:detection, Date: (today - 19), Time: now)
      expect(described_class.station_age_days(now: now)).to eq(19)
    end

    it 'is zero before anything is heard' do
      expect(described_class.station_age_days(now: now)).to eq(0)
    end
  end

  describe '#coverage_24h — was the mic up each hour' do
    let(:day) { Date.new(2026, 7, 2) } # yesterday, within heartbeat retention

    def coverage(date)
      described_class.new(date: date, now: date.end_of_day).to_h[:coverage_24h]
    end

    it 'is nil when the station has never sent a heartbeat (unknown → drawn as covered)' do
      expect(coverage(day)).to be_nil
    end

    it 'marks an hour up when it had a heartbeat OR a detection, down otherwise' do
      Heartbeat.create!(at: Time.zone.local(2026, 7, 2, 3, 30))
      create(:detection, Sci_Name: 'Turdus merula', Com_Name: 'Blackbird', Confidence: 0.9,
                         Date: '2026-07-02', Time: '05:00:00')

      result = coverage(day)
      expect(result.length).to eq(24)
      expect(result[3]).to be(true)  # a heartbeat
      expect(result[5]).to be(true)  # a detection also proves the loop was live
      expect(result[0]).to be(false) # neither → down
    end

    it 'is nil for a day older than heartbeats are kept, and for an unfinished today' do
      Heartbeat.create!(at: Time.zone.local(2026, 7, 2, 3, 30))
      expect(coverage(Date.new(2026, 6, 1))).to be_nil # pruned — can't assess
      expect(coverage(today)).to be_nil                # not a finished day
    end
  end

  describe 'listening coverage' do
    # The station being DOWN and the birds being quiet produce the same low count, and only
    # one of them is a fact about birds. Calling a gap "quieter than usual" is the failure
    # that matters most here, so the pace verdict is withheld when coverage is incomplete.
    def facts_with(live:, elapsed:)
      facts = described_class.new(date: Date.current)
      facts.define_singleton_method(:listening) { { hours_live: live, hours_elapsed: elapsed } }
      facts.define_singleton_method(:daily_baseline) { 100.0 }
      facts.define_singleton_method(:detections_today) { 10 }
      facts
    end

    it 'makes no pace claim when the recorder missed part of the day' do
      expect(facts_with(live: 7, elapsed: 18).send(:activity_note)).to be_nil
    end

    it 'still judges pace when the recorder was up throughout' do
      expect(facts_with(live: 18, elapsed: 18).send(:activity_note)).not_to be_nil
    end

    it 'treats never-having-ticked as unknown rather than as a gap' do
      facts = described_class.new(date: Date.current)
      facts.define_singleton_method(:listening) { nil }
      expect(facts.send(:fully_listening?)).to be(true)
    end
  end
end
