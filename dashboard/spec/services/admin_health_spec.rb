require 'rails_helper'

RSpec.describe AdminHealth do
  let(:now) { Time.zone.local(2026, 7, 4, 12, 0, 0) }

  it 'reports an empty, quiet box when nothing has been heard' do
    snap = described_class.snapshot(now: now)
    expect(snap[:listening][:freshness]).to eq(:none)
    expect(snap[:listening][:last_heard_at]).to be_nil
    expect(snap[:listening][:detections_all_time]).to eq(0)
    expect(snap[:alerts][:events_pending]).to eq(0)
    expect(snap[:system][:env]).to eq('test')
  end

  it 'marks a recent detection as fresh' do
    create(:detection, Date: now.to_date, Time: now - 5.minutes)
    snap = described_class.snapshot(now: now)
    expect(snap[:listening][:freshness]).to eq(:fresh)
    expect(snap[:listening][:last_heard_at]).to be_within(60.seconds).of(now - 5.minutes)
    expect(snap[:listening][:detections_all_time]).to eq(1)
  end

  it 'marks a day-old detection as stale' do
    create(:detection, Date: (now - 2.days).to_date, Time: now - 2.days)
    expect(described_class.snapshot(now: now)[:listening][:freshness]).to eq(:stale)
  end

  # The heartbeat's whole point: a quiet spell (no detections for hours) still reads fresh
  # as long as the mic → BirdNET loop is ticking. A quiet window is a true zero, not a stall.
  it 'stays fresh through a quiet spell while the mic keeps ticking' do
    create(:detection, Date: (now - 8.hours).to_date, Time: now - 8.hours)
    create(:heartbeat, at: now - 2.minutes)
    snap = described_class.snapshot(now: now)
    expect(snap[:listening][:freshness]).to eq(:fresh)
    expect(snap[:listening][:last_alive_at]).to be_within(60.seconds).of(now - 2.minutes)
  end

  # The converse: when the ticks stop (mic down) and nothing is heard lately, the feed is
  # genuinely stalled — missing data, not a quiet zero.
  it 'goes stale when the heartbeat stops and nothing is heard' do
    create(:heartbeat, at: now - 9.hours)
    expect(described_class.snapshot(now: now)[:listening][:freshness]).to eq(:stale)
  end

  it 'surfaces the unsent event backlog' do
    create(:event, notified_at: nil)
    create(:event, event_type: 'rarity', notified_at: now)
    snap = described_class.snapshot(now: now)
    expect(snap[:alerts][:events_total]).to eq(2)
    expect(snap[:alerts][:events_pending]).to eq(1)
  end
end
