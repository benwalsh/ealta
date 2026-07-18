require 'rails_helper'

RSpec.describe EmailSuppression do
  describe 'hard bounce' do
    it 'suppresses immediately on the first occurrence' do
      described_class.record_hard_bounce!('gone@example.com')
      expect(described_class.suppressed?('gone@example.com')).to be(true)
      expect(described_class.find_by(email: 'gone@example.com').reason).to eq('hard_bounce')
    end
  end

  describe 'complaint' do
    it 'suppresses immediately and permanently' do
      described_class.record_complaint!('cross@example.com')
      expect(described_class.suppressed?('cross@example.com')).to be(true)
      expect(described_class.find_by(email: 'cross@example.com').reason).to eq('complaint')
    end

    it 'keeps the original reason and time if another event arrives (first-write-wins)' do
      described_class.record_complaint!('cross@example.com')
      first = described_class.find_by(email: 'cross@example.com').suppressed_at
      described_class.record_hard_bounce!('cross@example.com')
      row = described_class.find_by(email: 'cross@example.com')
      expect(row.reason).to eq('complaint')
      expect(row.suppressed_at).to eq(first)
    end
  end

  describe 'soft bounce' do
    it 'tolerates a few, then suppresses after the limit of consecutive failures' do
      (described_class::SOFT_BOUNCE_LIMIT - 1).times { described_class.record_soft_bounce!('slow@example.com') }
      expect(described_class.suppressed?('slow@example.com')).to be(false)

      described_class.record_soft_bounce!('slow@example.com')
      expect(described_class.suppressed?('slow@example.com')).to be(true)
      expect(described_class.find_by(email: 'slow@example.com').reason).to eq('soft_bounce')
    end

    it 'resets the streak on a confirmed delivery, so it never reaches the limit' do
      (described_class::SOFT_BOUNCE_LIMIT - 1).times { described_class.record_soft_bounce!('slow@example.com') }
      described_class.record_delivery!('slow@example.com')
      described_class.record_soft_bounce!('slow@example.com')
      expect(described_class.suppressed?('slow@example.com')).to be(false)
    end
  end

  describe '.suppressed?' do
    it 'is case- and whitespace-insensitive' do
      described_class.record_complaint!('Mixed@Example.com')
      expect(described_class.suppressed?('  mixed@example.com ')).to be(true)
    end

    it 'is false for an address with only soft bounces below the limit' do
      described_class.record_soft_bounce!('ok@example.com')
      expect(described_class.suppressed?('ok@example.com')).to be(false)
    end
  end
end
