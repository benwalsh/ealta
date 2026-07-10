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
end
