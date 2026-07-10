require 'rails_helper'

RSpec.describe BirdMask do
  describe '#opaque_at' do
    it 'reads packed bits MSB-first, row-major' do
      # 2×2 mask, only the top-left cell opaque -> first bit set -> byte 0x80.
      mask = described_class.new(2, 2, "\x80".b)
      expect(mask.opaque_at(0.0, 0.0)).to be(true)   # top-left
      expect(mask.opaque_at(0.9, 0.0)).to be(false)  # top-right
      expect(mask.opaque_at(0.0, 0.9)).to be(false)  # bottom-left
    end
  end

  describe '.for' do
    it 'returns nil for a slug we have no silhouette for' do
      expect(described_class.for('not-a-real-bird-slug')).to be_nil
    end
  end
end
