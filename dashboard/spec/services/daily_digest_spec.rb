require 'rails_helper'

RSpec.describe DailyDigest do
  let(:date) { Date.yesterday }

  before { allow(Notifier).to receive(:enabled?).and_return(true) }

  def digest_follower(sci)
    create(:user).tap { |u| u.subscriptions.create!(alert_type: 'species', sci_name: sci, cadence: 'digest') }
  end

  it 'sends to a digest follower when their bird was heard that day' do
    user = digest_follower('Crex crex')
    create(:detection, Sci_Name: 'Crex crex', Date: date) # credible (0.8), so it tallies
    expect(Notifier).to receive(:deliver_digest).with(hash_including(user: user, date: date)).and_return(true)
    expect(described_class.deliver_all(date: date)).to eq(1)
  end

  it 'bundles a standing-rule event for a digest rule subscriber' do
    create(:user).subscriptions.create!(alert_type: 'rarity', cadence: 'digest')
    create(:event, event_type: 'rarity', sci_name: 'Crex crex', occurred_on: date)
    expect(Notifier).to receive(:deliver_digest).and_return(true)
    expect(described_class.deliver_all(date: date)).to eq(1)
  end

  it 'sends the daily letter to a roundup subscriber even with no follows' do
    create(:user).subscriptions.create!(alert_type: 'roundup', cadence: 'digest')
    expect(Notifier).to receive(:deliver_digest).and_return(true)
    expect(described_class.deliver_all(date: date)).to eq(1)
  end

  it 'ignores immediate-cadence subscribers (already emailed live)' do
    create(:user).subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', cadence: 'immediate')
    create(:detection, Sci_Name: 'Crex crex', Date: date)
    expect(Notifier).not_to receive(:deliver_digest)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end

  it 'is idempotent — a second run the same day sends nothing' do
    digest_follower('Crex crex')
    create(:detection, Sci_Name: 'Crex crex', Date: date)
    allow(Notifier).to receive(:deliver_digest).and_return(true)
    described_class.deliver_all(date: date)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end

  it "marks the day done even with nothing to say, so it won't rescan" do
    user = digest_follower('Crex crex') # followed bird not heard, no roundup
    expect(Notifier).not_to receive(:deliver_digest)
    described_class.deliver_all(date: date)
    expect(user.reload.last_digest_on).to eq(date)
  end

  it 'does nothing when alerts are disabled (no ALERTS_FROM)' do
    allow(Notifier).to receive(:enabled?).and_return(false)
    digest_follower('Crex crex')
    create(:detection, Sci_Name: 'Crex crex', Date: date)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end
end
