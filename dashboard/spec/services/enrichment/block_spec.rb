require 'rails_helper'

RSpec.describe Enrichment::Block do
  def block(overrides = {})
    base = { type: 'fact', id: 'x', text: 'A fact.',
             sources: [{ name: 'BirdWatch Ireland', url: 'https://birdwatchireland.ie' }] }
    described_class.from(base.merge(overrides))
  end

  it 'accepts a well-formed sourced fact' do
    expect(block).to be_valid
  end

  it "accepts a station_reading with no sources (the station's own data)" do
    reading = described_class.from(type: 'station_reading', id: 'first', text: 'First heard at 08:35.', sources: [])
    expect(reading).to be_valid
  end

  it 'rejects a fact with no source' do
    expect(block(sources: [])).not_to be_valid
  end

  it 'rejects an unknown type' do
    expect(block(type: 'rumour')).not_to be_valid
  end

  it 'rejects a blank id' do
    expect(block(id: '')).not_to be_valid
  end

  it 'requires folklore to be gated' do
    folk = { type: 'folklore', id: 'f', quote: 'If the cuckoo sings…',
             sources: [{ name: "Schools' Collection", url: 'https://www.duchas.ie' }] }
    expect(described_class.from(folk)).not_to be_valid
    expect(described_class.from(folk.merge(gated: true))).to be_valid
  end

  it 'reads string-keyed hashes (as stored in the json column)' do
    b = described_class.from('type' => 'fact', 'id' => 'x', 'sources' => [{ 'name' => 'BWI', 'url' => 'u' }])
    expect(b).to be_valid
    expect(b.type).to eq('fact')
  end
end
