require 'rails_helper'

RSpec.describe DayHero do
  let(:as_of) { Date.new(2026, 7, 7) }

  def item(sci, importance:, count: 1)
    { sci_name: sci, importance: importance, call_count: count }
  end

  def featured(sci, date:)
    JournalEntry.create!(date: date, hero_sci_name: sci)
  end

  describe '.pick' do
    it 'returns nil on a birdless day' do
      expect(described_class.pick([], as_of: as_of)).to be_nil
    end

    it 'leads with a rarity over a much louder everyday bird' do
      items = [item('Passer domesticus', importance: 5, count: 40),
               item('Pluvialis apricaria', importance: 100, count: 1)]
      expect(described_class.pick(items, as_of: as_of)[:sci_name]).to eq('Pluvialis apricaria')
    end

    it 'lets a rarity lead even when it led the day before (never rested)' do
      featured('Pluvialis apricaria', date: as_of - 1)
      items = [item('Passer domesticus', importance: 5, count: 40),
               item('Pluvialis apricaria', importance: 100, count: 1)]
      expect(described_class.pick(items, as_of: as_of)[:sci_name]).to eq('Pluvialis apricaria')
    end

    it 'rests an everyday bird that led recently, so a fresh one leads instead' do
      featured('Passer domesticus', date: as_of - 3)
      items = [item('Passer domesticus', importance: 5, count: 40), # loudest, but just featured
               item('Larus argentatus', importance: 5, count: 10)]
      expect(described_class.pick(items, as_of: as_of)[:sci_name]).to eq('Larus argentatus')
    end

    it 'does not rest a bird whose last turn was longer ago than the cooldown' do
      featured('Passer domesticus', date: as_of - 200)
      items = [item('Passer domesticus', importance: 5, count: 40),
               item('Larus argentatus', importance: 5, count: 10)]
      expect(described_class.pick(items, as_of: as_of)[:sci_name]).to eq('Passer domesticus')
    end

    it 'falls back to the loudest when every everyday candidate led recently' do
      featured('Passer domesticus', date: as_of - 2)
      featured('Larus argentatus', date: as_of - 5)
      items = [item('Passer domesticus', importance: 5, count: 40),
               item('Larus argentatus', importance: 5, count: 10)]
      expect(described_class.pick(items, as_of: as_of)[:sci_name]).to eq('Passer domesticus')
    end
  end
end
