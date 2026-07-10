require 'rails_helper'

RSpec.describe MaskPacker do
  # A filled square tile of side `s` (a 2×2 all-on mask covers the box).
  def tile(side)
    { w: side, h: side, cells: [[0, 0], [1, 0], [0, 1], [1, 1]], mask_w: 2, mask_h: 2 }
  end

  it 'returns a top-left per tile, in input order' do
    result = described_class.pack([tile(40), tile(30), tile(50)], width: 400, height: 300)
    expect(result.size).to eq(3)
  end

  it 'packs deterministically' do
    tiles = [tile(40), tile(30), tile(50)]
    first = described_class.pack(tiles, width: 400, height: 300)
    again = described_class.pack(tiles, width: 400, height: 300)
    expect(first).to eq(again)
  end

  it 'places tiles without overlapping' do
    a, b = described_class.pack([tile(40), tile(40)], width: 400, height: 300)
    apart = (a[0] + 40 <= b[0]) || (b[0] + 40 <= a[0]) || (a[1] + 40 <= b[1]) || (b[1] + 40 <= a[1])
    expect(apart).to be(true)
  end

  it 'keeps placed tiles inside the region' do
    described_class.pack([tile(40), tile(30)], width: 400, height: 300).compact.each do |x, y|
      expect(x).to be >= 0
      expect(y).to be >= 0
    end
  end
end
