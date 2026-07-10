require 'rails_helper'

RSpec.describe Sparkline do
  describe '.paths' do
    it 'emits a smooth curve (cubic béziers, no vertical spikes) for real data' do
      counts = [0, 0, 1, 3, 8, 12, 9, 5, 4, 6, 10, 14, 11, 7, 5, 3, 2, 1, 0, 0, 1, 2, 3, 1]
      result = described_class.paths(counts)

      expect(result.path).to start_with('M ')
      expect(result.path).to include('C ') # smoothed, not straight L segments
      expect(result.path).not_to include(' L ') # the stroke is all curves
      # the fill re-uses the curve then closes to the baseline
      expect(result.fill).to start_with(result.path)
      expect(result.fill).to match(/ L [\d.]+ #{Sparkline::H} L [\d.]+ #{Sparkline::H} Z\z/o)
    end

    it 'rests as a flat gentle line (not a spike) when the day is silent' do
      result = described_class.paths(Array.new(24, 0))
      # a single straight segment near the baseline, no peaks
      expect(result.path).to match(/\AM \d/)
      expect(result.path).to include(' L ')
      expect(result.path).not_to include('C ')
    end

    it 'rests flat when given too few points to form a curve' do
      expect(described_class.paths([]).path).not_to include('C ')
      expect(described_class.paths([5]).path).not_to include('C ')
    end

    it 'keeps every coordinate inside the viewBox' do
      result = described_class.paths([0, 0, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      coords = result.path.scan(/-?\d+\.?\d*/).map(&:to_f)
      xs = coords.each_slice(2).map(&:first)
      ys = coords.each_slice(2).map(&:last)
      expect(xs.min).to be >= 0
      expect(xs.max).to be <= Sparkline::W
      expect(ys.min).to be >= 0
      expect(ys.max).to be <= Sparkline::H
    end
  end

  describe 'blind spots (coverage → data-availability bands)' do
    let(:busy) { Array.new(24, 5) }

    it 'has no gaps, and one continuous curve, when every bucket was covered' do
      result = described_class.paths(busy, coverage: Array.new(24, true))
      expect(result.gaps).to eq([])
      expect(result.path.scan('M ').size).to eq(1)
    end

    it 'bands a mic-down stretch (real x-span + bucket range) and breaks the curve around it' do
      coverage = Array.new(24, true)
      (8..15).each { |i| coverage[i] = false } # mic down mid-window
      result = described_class.paths(busy, coverage: coverage)

      expect(result.gaps.size).to eq(1)
      gap = result.gaps.first
      expect(gap).to include(from: 8, to: 15)               # the uncovered bucket range
      expect(gap[:x0]).to be < gap[:x1]                     # a real span, not a zero-width line
      expect(gap[:x1]).to be <= Sparkline::W
      expect(result.path.scan('M ').size).to eq(2)          # curve split into two runs, never joined
    end

    it 'still bands a blind spot even when the covered part was silent' do
      coverage = Array.new(24, true)
      (0..5).each { |i| coverage[i] = false }
      result = described_class.paths(Array.new(24, 0), coverage: coverage)
      expect(result.gaps.map { |g| [g[:from], g[:to]] }).to eq([[0, 5]])
    end

    it 'assumes full coverage (no gaps) when there is no coverage signal at all' do
      expect(described_class.paths(busy, coverage: nil).gaps).to eq([])
      expect(described_class.paths(busy, coverage: Array.new(24, false)).gaps).to eq([])
    end
  end
end
