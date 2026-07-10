require 'rails_helper'

RSpec.describe EnrichmentBundle do
  it 'is one bundle per species per date' do
    described_class.create!(sci_name: 'Cuculus canorus', date: Date.current, blocks: [])
    dup = described_class.new(sci_name: 'Cuculus canorus', date: Date.current, blocks: [])
    expect(dup).not_to be_valid
  end

  it 'allows the same species on a different date (folklore re-rolls daily)' do
    described_class.create!(sci_name: 'Cuculus canorus', date: Date.current, blocks: [])
    expect(described_class.new(sci_name: 'Cuculus canorus', date: Date.yesterday, blocks: [])).to be_valid
  end

  it 'hands the assembler only blocks that honour the contract' do
    bundle = described_class.create!(sci_name: 'Crex crex', date: Date.current, blocks: [
                                       { type: 'fact', id: 'ok', sources: [{ name: 'BWI', url: 'u' }] },
                                       { type: 'fact', id: 'bad', sources: [] } # dropped: unsourced
                                     ])
    expect(bundle.block_objects.map(&:id)).to eq(['ok'])
  end
end
