require 'rails_helper'

RSpec.describe CollagePresenter do
  # Nodes carry second-language names + illustration paths, so run against the bilingual
  # sample fixture (with its art fixtures), not the English-only example default.
  around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

  def tally(sci, count)
    Detection::SpeciesTally.new(sci, count, nil, 0.8)
  end

  describe '#nodes' do
    it 'returns one node per species' do
      presenter = described_class.new([tally('Erithacus rubecula', 5), tally('Turdus merula', 3)])
      expect(presenter.nodes.size).to eq(2)
    end

    it 'keeps every node within the panel bounds' do
      tallies = [['Erithacus rubecula', 12], ['Turdus merula', 9], ['Hirundo rustica', 4],
                 ['Numenius arquata', 1]].map { |sci, count| tally(sci, count) }
      presenter = described_class.new(tallies, width: 800, height: 480)
      presenter.nodes.each do |node|
        expect(node.cx - (node.w / 2)).to be >= 0
        expect(node.cx + (node.w / 2)).to be <= 800
        expect(node.cy + (node.h / 2)).to be <= 480
      end
    end

    it 'carries the bird identity for the caption' do
      node = described_class.new([tally('Erithacus rubecula', 5)]).nodes.first
      expect(node.ga).to eq('Spideog')
      expect(node.count).to eq(5)
    end

    it 'exposes a perched image (never a -2 flight pose) for the hits strip' do
      # Enough species that some get flight poses; every perch_image must still be perched.
      tallies = ['Erithacus rubecula', 'Turdus merula', 'Hirundo rustica', 'Pica pica', 'Passer domesticus'].
                each_with_index.map { |sci, i| tally(sci, 10 - i) }
      described_class.new(tallies).nodes.each do |node|
        expect(node.perch_image).to be_present
        expect(node.perch_image).not_to include('-2.png')
      end
    end

    it 'compresses the size range so the loudest bird cannot dwarf the quietest' do
      tallies = [tally('Erithacus rubecula', 100), tally('Numenius arquata', 1)]
      radii = described_class.new(tallies).nodes.map(&:r)
      expect(radii.max / radii.min).to be <= (CollagePresenter::SIZE_RATIO + 0.01)
    end

    it 'normalises each bird to the same visual area regardless of aspect' do
      tallies = [tally('Pica pica', 8), tally('Erithacus rubecula', 5)]
      described_class.new(tallies).nodes.each do |node|
        # w·h ≈ (2r)² — a wide bird gets a wider, shorter box of equal area.
        expect(node.w * node.h).to be_within(1).percent_of((2 * node.r)**2)
      end
    end

    it 'handles an empty day' do
      expect(described_class.new([]).nodes).to eq([])
    end
  end

  describe 'illustration URLs' do
    it 'serves the local /birds PNG at full quality when no CDN is configured' do
      node = described_class.new([tally('Erithacus rubecula', 5)]).nodes.first
      expect(node.image).to start_with('/birds/erithacus-rubecula.png?v=')
      expect(node.image).not_to include('.webp')
    end

    it 'points at the pre-sized CDN WebP when ILLUSTRATIONS_BASE_URL is set' do
      # A trailing slash on the base must not double up in the URL.
      allow(Station).to receive(:setting).and_call_original
      allow(Station).to receive(:setting).with('illustrations.base_url', env: 'ILLUSTRATIONS_BASE_URL').
        and_return('https://cdn.example.net/art/')

      node = described_class.new([tally('Erithacus rubecula', 5)]).nodes.first
      expect(node.image).to start_with('https://cdn.example.net/art/erithacus-rubecula.webp?v=')
    end
  end
end
