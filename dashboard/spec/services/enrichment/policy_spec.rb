require 'rails_helper'

RSpec.describe Enrichment::Policy do
  describe '.refresh_interval_days' do
    it 'refreshes a notable bird daily and a routine one rarely' do
      expect(described_class.refresh_interval_days(100)).to eq(1)  # all-time first
      expect(described_class.refresh_interval_days(80)).to eq(1)   # seasonal return
      expect(described_class.refresh_interval_days(60)).to eq(1)   # rare_local
      expect(described_class.refresh_interval_days(40)).to eq(30)  # unusual volume
      expect(described_class.refresh_interval_days(5)).to eq(180)  # routine
    end
  end

  describe '.due?' do
    let(:sci) { 'Cuculus canorus' }
    let(:today) { Date.new(2026, 4, 20) }

    def bundle_on(date)
      EnrichmentBundle.create!(
        sci_name: sci, date: date, common_name: 'Common Cuckoo', irish_name: 'Cuach',
        blocks: [{ type: 'fact', id: 'f', text: 'A brood parasite.',
                   sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/Common_cuckoo' }] }]
      )
    end

    it 'is due when nothing has ever been sourced' do
      expect(described_class.due?(sci, 80, as_of: today)).to be(true)
    end

    it 'is due when the only bundle holds no usable blocks' do
      EnrichmentBundle.create!(sci_name: sci, date: today, common_name: 'Common Cuckoo', blocks: [])
      expect(described_class.due?(sci, 80, as_of: today)).to be(true)
    end

    it 'a notable bird sourced yesterday is due again today (daily during its window)' do
      bundle_on(today - 1)
      expect(described_class.due?(sci, 80, as_of: today)).to be(true)
    end

    it 'a notable bird sourced today is not due again today' do
      bundle_on(today)
      expect(described_class.due?(sci, 80, as_of: today)).to be(false)
    end

    it 'a routine bird (house sparrow) sourced weeks ago is not yet due' do
      bundle_on(today - 30)
      expect(described_class.due?(sci, 5, as_of: today)).to be(false)   # 30 < 180
    end

    it 'a routine bird is due again only after the long backoff' do
      bundle_on(today - 200)
      expect(described_class.due?(sci, 5, as_of: today)).to be(true)    # 200 >= 180
    end
  end
end
