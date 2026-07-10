require 'rails_helper'

RSpec.describe Conservation do
  it 'returns the BoCCI status for listed species' do
    expect(described_class.status('Crex crex')).to eq('red') # Corncrake
    expect(described_class.status('Passer domesticus')).to eq('amber') # House Sparrow
    expect(described_class.status('Erithacus rubecula')).to eq('green') # Robin
  end

  it 'returns nil for unlisted, unknown, or absent species' do
    expect(described_class.status('Phasianus colchicus')).to be_nil # unlisted (introduced)
    expect(described_class.status('Totally madeup')).to be_nil
  end

  it 'exposes a display name and a one-line note' do
    expect(described_class.name('Crex crex')).to eq('Red')
    expect(described_class.note('Crex crex')).to match(/conservation concern in Ireland/i)
    expect(described_class.name('Totally madeup')).to be_nil
  end
end
