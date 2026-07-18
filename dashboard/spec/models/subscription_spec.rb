require 'rails_helper'

RSpec.describe Subscription do
  it 'requires a known alert_type' do
    expect(build(:subscription, alert_type: 'nonsense')).not_to be_valid
  end

  it 'requires a sci_name for species subscriptions' do
    expect(build(:subscription, alert_type: 'species', sci_name: nil)).not_to be_valid
  end

  it 'allows a species-less standing rule' do
    expect(build(:subscription, alert_type: 'rarity', sci_name: nil)).to be_valid
  end

  it 'delegates email to the user' do
    sub = create(:subscription, user: create(:user, email: 'watcher@example.com'))
    expect(sub.email).to eq('watcher@example.com')
  end

  describe 'scopes' do
    it 'for_species matches only active species subscriptions' do
      match = create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      create(:subscription, alert_type: 'species', sci_name: 'Crex crex', active: false)
      create(:subscription, alert_type: 'rarity', sci_name: nil)
      expect(described_class.for_species('Crex crex')).to contain_exactly(match)
    end
  end
end
