require 'rails_helper'

RSpec.describe Setting do
  it 'returns the default when a key is unset' do
    expect(described_class.get('nope', 'fallback')).to eq('fallback')
    expect(described_class.get('nope')).to be_nil
  end

  it 'round-trips a value' do
    described_class.set('greeting', 'dia dhuit')
    expect(described_class.get('greeting')).to eq('dia dhuit')
  end

  it 'upserts rather than duplicating a key' do
    described_class.set('lang', 'ga')
    described_class.set('lang', 'en')
    expect(described_class.where(key: 'lang').count).to eq(1)
    expect(described_class.get('lang')).to eq('en')
  end
end
