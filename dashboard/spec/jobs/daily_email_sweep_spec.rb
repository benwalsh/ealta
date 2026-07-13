require 'rails_helper'

RSpec.describe DailyEmailSweep do
  it 'sources the day’s enrichment first, then delivers the digests, for the given date' do
    date = Date.new(2026, 7, 4)
    expect(Enrichment::Builder).to receive(:run).with(date: date).ordered
    expect(DailyLetter).to receive(:deliver_all).with(date: date).ordered
    described_class.perform_now(date.to_s)
  end

  it 'defaults to yesterday — the last complete day' do
    allow(Enrichment::Builder).to receive(:run)
    expect(DailyLetter).to receive(:deliver_all).with(date: Date.yesterday)
    described_class.perform_now
  end

  it 'is enqueueable on the default queue' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue('default')
  end
end
