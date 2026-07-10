require 'rails_helper'

RSpec.describe DigestFacts do
  let(:date) { Date.yesterday }
  let(:user) { create(:user) }

  it 'lists a followed bird heard that day with its count' do
    user.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', cadence: 'digest')
    create_list(:detection, 3, Sci_Name: 'Crex crex', Date: date, Confidence: 0.9)
    facts = described_class.for(user: user, date: date)
    expect(facts.follows).to contain_exactly(hash_including(sci: 'Crex crex', count: 3))
    expect(facts).to be_any
  end

  it 'excludes immediate-cadence follows (those go out live, not in the digest)' do
    user.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', cadence: 'immediate')
    create(:detection, Sci_Name: 'Crex crex', Date: date)
    expect(described_class.for(user: user, date: date).follows).to be_empty
  end

  it 'includes standing-rule events the user takes by digest' do
    user.subscriptions.create!(alert_type: 'rarity', cadence: 'digest')
    create(:event, event_type: 'rarity', sci_name: 'Crex crex', occurred_on: date)
    facts = described_class.for(user: user, date: date)
    expect(facts.alerts).to contain_exactly(hash_including(kind: 'rarity', sci: 'Crex crex'))
  end

  it 'includes the general station day only for a roundup subscriber' do
    plain = described_class.for(user: user, date: date)
    expect(plain.roundup).to be_nil

    user.subscriptions.create!(alert_type: 'roundup', cadence: 'digest')
    expect(described_class.for(user: user, date: date).roundup).to include(:species_today, :detections_today)
  end

  it 'is empty (nothing to send) for a user with no follows, alerts or roundup' do
    user.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', cadence: 'digest')
    expect(described_class.for(user: user, date: date)).not_to be_any # bird wasn't heard
  end
end
