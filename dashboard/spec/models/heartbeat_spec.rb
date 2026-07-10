require 'rails_helper'

RSpec.describe Heartbeat do
  let(:now) { Time.zone.local(2026, 7, 4, 12, 0, 0) }

  it 'is nil when the listener has never checked in' do
    expect(described_class.last_at).to be_nil
  end

  it 'reports the most recent tick' do
    create(:heartbeat, at: now - 10.minutes)
    create(:heartbeat, at: now - 2.minutes)
    expect(described_class.last_at).to be_within(1.second).of(now - 2.minutes)
  end

  describe '.coverage' do
    # The distinction the whole thing exists for: a bucket with a tick was OPERATIVE
    # (a true zero if it heard nothing); a bucket with no tick is missing data.
    it 'marks the buckets the listener was alive for, leaving the rest missing' do
      start = now - 3.hours
      width = 3600.0 # one-hour buckets
      create(:heartbeat, at: start + 30.minutes) # bucket 0
      create(:heartbeat, at: start + 2.hours + 10.minutes) # bucket 2
      expect(described_class.coverage(start, width, 3)).to eq([true, false, true])
    end
  end
end
