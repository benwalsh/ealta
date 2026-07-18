require 'rails_helper'

RSpec.describe JournalEntry do
  before { travel_to Time.zone.local(2026, 7, 8, 9, 0) } # "yesterday" is 2026-07-07

  let(:yesterday) { Date.new(2026, 7, 7) }
  let(:narration) do
    { bullets: { en: ['A quiet day, the usual sparrows.'], ga: ['Lá ciúin.'] },
      source: 'facts', sources: [{ host: 'duchas.ie', url: 'https://www.duchas.ie/x' }] }
  end

  describe '.for' do
    it 'builds and freezes a completed day once, reading the frozen row back thereafter' do
      # narrated exactly once: the first .for builds, the second reads the frozen row.
      expect(DayNarrator).to receive(:narrate).once.and_return(narration)
      first = described_class.for(yesterday)

      expect(first).to be_persisted
      expect(first.date).to eq(yesterday)
      expect(first.bullets['en']).to eq(['A quiet day, the usual sparrows.'])
      expect(first.source).to eq('facts')

      second = described_class.for(yesterday)
      expect(second.id).to eq(first.id)
    end

    it 'refuses today and the future (an unfinished day cannot be a diary entry)' do
      expect(described_class.for(Date.new(2026, 7, 8))).to be_nil
      expect(described_class.for(Date.new(2026, 7, 9))).to be_nil
    end

    it 'leaves an outage day (detections but a thin template) unsaved, so a later view retries it' do
      create(:detection, Sci_Name: 'Turdus merula', Com_Name: 'Blackbird', Confidence: 0.9, Date: yesterday)
      allow(DayNarrator).to receive(:narrate).and_return(narration.merge(source: 'template'))
      entry = described_class.for(yesterday)

      expect(entry).not_to be_persisted
      expect(described_class.count).to eq(0)
    end

    it 'freezes an empty day (no detections) even when template, to record whether it was offline' do
      allow(DayNarrator).to receive(:narrate).and_return(narration.merge(source: 'template'))
      entry = described_class.for(yesterday) # no detections created → will never narrate to more

      expect(entry).to be_persisted
      expect(entry.source).to eq('template')
    end

    it 'narrates the requested completed day (end-of-day, so the day reads as finished)' do
      allow(DayNarrator).to receive(:narrate).and_return(narration)
      expect(DailyFacts).to receive(:for).with(date: yesterday, now: yesterday.end_of_day).and_call_original
      described_class.for(yesterday)
    end

    it 'freezes the day hero alongside the prose' do
      create(:detection, Sci_Name: 'Pluvialis apricaria', Com_Name: 'European Golden Plover',
                         Confidence: 0.9, Date: yesterday)
      allow(DayNarrator).to receive(:narrate).and_return(narration)

      expect(described_class.for(yesterday).hero_sci_name).to eq('Pluvialis apricaria')
    end
  end
end
