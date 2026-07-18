require 'rails_helper'

RSpec.describe MoonPhase do
  # The point of the drawn moon is that the SHAPE is right, so these assert the geometry the
  # path encodes — not merely that a string comes back. The lit region is bounded by the outer
  # limb on the lit side and the terminator half-ellipse (rx = |1 - 2·illumination| · radius),
  # so rx and the two sweep flags together fix how much is lit and which limb it sits on.
  # Northern hemisphere: waxing lights the RIGHT limb, waning the left.
  def arcs(path)
    path.scan(/A([\d.]+),([\d.]+) 0 0 (\d) (\d+),(\d+)/).map do |rx, ry, sweep, _x, _y|
      { rx: rx.to_f, ry: ry.to_f, sweep: sweep.to_i }
    end
  end

  describe '.path' do
    it 'draws nothing at new moon — the empty disc outline is the reading' do
      expect(described_class.path(0, true)).to be_nil
    end

    it 'fills the whole disc at full moon (terminator ellipse spans the full radius)' do
      limb, terminator = arcs(described_class.path(100, true))
      expect(limb[:rx]).to eq(9.0)
      expect(terminator[:rx]).to eq(9.0)
    end

    it 'flattens the terminator to a straight edge at the quarters' do
      # rx = 0 makes SVG render the arc as a line: exactly half the disc, split down the middle.
      expect(arcs(described_class.path(50, true)).last[:rx]).to eq(0.0)
      expect(arcs(described_class.path(50, false)).last[:rx]).to eq(0.0)
    end

    it 'narrows the terminator as illumination grows toward full' do
      # |1 - 2k|·r: widest at the extremes, zero at the quarters.
      rx = ->(pct) { arcs(described_class.path(pct, true)).last[:rx] }
      expect(rx.call(10)).to be > rx.call(30)
      expect(rx.call(30)).to be > rx.call(50)
      expect(rx.call(70)).to be > rx.call(50)
    end

    it 'lights the right limb waxing and the left limb waning' do
      # The limb arc is the first: sweep 1 sweeps through the right of the disc, 0 the left.
      expect(arcs(described_class.path(25, true)).first[:sweep]).to eq(1)
      expect(arcs(described_class.path(25, false)).first[:sweep]).to eq(0)
    end

    it 'bulges the terminator away from the lit limb for a gibbous moon' do
      # Crescent and gibbous differ only in which way the terminator curves — the sweep flag.
      waxing_crescent = arcs(described_class.path(25, true)).last[:sweep]
      waxing_gibbous  = arcs(described_class.path(75, true)).last[:sweep]
      expect(waxing_crescent).not_to eq(waxing_gibbous)
    end

    it 'mirrors a waning shape against its waxing counterpart' do
      waxing = arcs(described_class.path(25, true))
      waning = arcs(described_class.path(25, false))
      expect(waning.first[:sweep]).not_to eq(waxing.first[:sweep])
      expect(waning.last[:sweep]).not_to eq(waxing.last[:sweep])
      expect(waning.last[:rx]).to eq(waxing.last[:rx]) # same amount lit, other limb
    end
  end

  # Ink reads as dark on paper and on the panel's e-ink, so the views fill the SHADOW, never
  # the lit part — filling the lit part draws a photographic negative (a full moon coming out
  # solid black). These pin that polarity so it can't quietly invert again.
  describe '.shadow' do
    it 'inks the whole disc at new moon — nothing is lit' do
      limb, terminator = arcs(described_class.shadow(0, true))
      expect(limb[:rx]).to eq(9.0)
      expect(terminator[:rx]).to eq(9.0)
    end

    it 'inks nothing at full moon — the open outline is the reading' do
      expect(described_class.shadow(100, true)).to be_nil
    end

    it 'shades the limb OPPOSITE the lit one' do
      # A waxing moon is lit on the right, so its shadow must sit on the left, and vice versa.
      expect(arcs(described_class.shadow(25, true)).first[:sweep]).to eq(0)  # shadow on the left
      expect(arcs(described_class.shadow(25, false)).first[:sweep]).to eq(1) # shadow on the right
    end

    it 'is exactly the complement of the lit region' do
      # Same terminator, other limb: the shadow of a 25%-waxing moon is the 75%-waning shape.
      expect(described_class.shadow(25, true)).to eq(described_class.path(75, false))
      expect(arcs(described_class.shadow(25, true)).last[:rx]).
        to eq(arcs(described_class.path(25, true)).last[:rx])
    end
  end

  describe '.for' do
    it 'carries the drawn shape and waxing sense alongside the name' do
      phase = described_class.for(Date.new(2026, 7, 18))
      expect(phase.illumination).to be_between(0, 100)
      expect(phase).to respond_to(:waxing, :path)
    end

    it 'waxes in the first half of the synodic month and wanes in the second' do
      new_moon = MoonPhase::KNOWN_NEW_MOON
      expect(described_class.for(new_moon + 5).waxing).to be(true)
      expect(described_class.for(new_moon + 22).waxing).to be(false)
    end

    it 'names the full moon at maximum illumination' do
      new_moon = MoonPhase::KNOWN_NEW_MOON
      full = described_class.for(new_moon + (MoonPhase::SYNODIC / 2).round)
      expect(full.illumination).to be > 99
      expect(full.name).to eq('Full Moon')
    end
  end
end
