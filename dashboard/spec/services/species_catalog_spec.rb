require 'rails_helper'

RSpec.describe SpeciesCatalog do
  before { described_class.reset! }

  # The bug this guards: in the cloud the illustration PNGs live on the CDN, not the app
  # container's disk — only masks.json ships in the image. The catalogue must come from that
  # manifest (BirdMask), never a filesystem glob, or "all species" collapses to the life list.
  it 'builds the library from the masks.json manifest, not the PNG files on disk' do
    # Slugs the manifest knows but with no PNG anywhere — they must still enter the catalogue.
    allow(BirdMask).to receive(:slugs).
      and_return(%w[haliaeetus-albicilla haliaeetus-albicilla-2 passer-domesticus])
    allow(BirdName).to receive(:scientific_names).
      and_return(['Haliaeetus albicilla', 'Passer domesticus', 'Turdus merula'])

    expect(described_class.all_sci).to include('Haliaeetus albicilla', 'Passer domesticus')
    expect(described_class.all_sci).not_to include('Turdus merula') # no mask → not illustrated
  end

  it 'counts a species once, ignoring its "-2" flight-pose variant' do
    allow(BirdMask).to receive(:slugs).and_return(%w[hirundo-rustica hirundo-rustica-2])
    allow(BirdName).to receive(:scientific_names).and_return(['Hirundo rustica'])

    expect(described_class.all_sci).to eq(['Hirundo rustica'])
  end
end
