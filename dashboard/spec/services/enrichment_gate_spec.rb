require 'rails_helper'

RSpec.describe EnrichmentGate do
  def item(sci, importance, common = sci, irish = nil)
    { sci_name: sci, common_name: common, irish_name: irish, importance: importance, flags: [] }
  end

  def facts(*items) = { items: items }

  it 'clears a bird at or above the notable bar (an all-time-first)' do
    f = facts(item('Cuculus canorus', DailyFacts::IMPORTANCE[:all_time_first], 'Common Cuckoo', 'Cuach'))
    expect(described_class.species_for(f)).to contain_exactly(
      { sci_name: 'Cuculus canorus', common_name: 'Common Cuckoo', irish_name: 'Cuach' }
    )
  end

  it 'clears a locally-rare bird (rare_local is exactly the bar)' do
    f = facts(item('Crex crex', DailyFacts::IMPORTANCE[:rare_local]))
    expect(described_class.species_for(f).pluck(:sci_name)).to eq(['Crex crex'])
  end

  it 'never clears a routine common bird, whatever its count' do
    f = facts(item('Passer domesticus', DailyFacts::IMPORTANCE[:routine]))
    expect(described_class.species_for(f)).to be_empty
  end

  it 'does not clear unusual_volume alone (importance 40, below the bar)' do
    f = facts(item('Sturnus vulgaris', DailyFacts::IMPORTANCE[:unusual_volume]))
    expect(described_class.species_for(f)).to be_empty
  end

  it 'returns [] for an empty or item-less day' do
    expect(described_class.species_for(facts)).to eq([])
    expect(described_class.species_for({})).to eq([])
  end

  it 'never returns a species absent from the facts items' do
    f = facts(item('Crex crex', DailyFacts::IMPORTANCE[:rare_local]))
    expect(described_class.species_for(f).pluck(:sci_name)).to all(eq('Crex crex'))
  end

  it 'ignores the watchlist — a follow never lowers the bar' do
    f = facts(item('Passer domesticus', DailyFacts::IMPORTANCE[:routine]))
    expect(described_class.species_for(f, watchlist: ['Passer domesticus'])).to be_empty
  end
end
