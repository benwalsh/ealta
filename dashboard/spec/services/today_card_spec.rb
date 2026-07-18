require 'rails_helper'

RSpec.describe TodayCard do
  # A fixed 'now' so the spans are deterministic regardless of when specs run.
  let(:now) { Time.zone.local(2026, 7, 4, 12, 0, 0) }

  it 'returns four anchors spanning the window from 0 to 1' do
    card = described_class.build(now: now, window_hours: 24)
    xs = card[:anchors].pluck(:x)
    expect(card[:anchors].size).to eq(4)
    expect(xs.first).to eq(0.0)
    expect(xs.last).to eq(1.0)
  end

  it 'labels a short window as clock times (same in both languages)' do
    card = described_class.build(now: now, window_hours: 24)
    last = card[:anchors].last
    expect(last[:en]).to match(/\A\d{2}:\d{2}\z/)
    expect(last[:ga]).to eq(last[:en])
  end

  it 'passes a no-data band through as a bare x-span, with nothing to caption' do
    # The band used to be painted as a grey slab with a "No data · 20:00–04:00" label over it.
    # Nothing is drawn there now — the curve just breaks — so there is no label to build, and
    # `offline` / `mic_hours` carry the fact in words instead.
    start = now - 24.hours
    gaps = described_class.send(:gap_labels, [{ x0: 233.4, x1: 466.7, from: 8, to: 15 }], now, start)
    expect(gaps.first).to eq(x0: 233.4, x1: 466.7)
  end

  it 'labels a multi-day window as dates, with the Irish month for ga' do
    card = described_class.build(now: now, window_hours: 168) # 7 days back → spans late June
    expect(card[:anchors].first[:en]).to match(/\d/)          # a date like '27 Jun'
    expect(card[:anchors].first[:ga]).to include('Meitheamh') # June, in Irish
  end

  it 'rescales the anchors with the window (24h clock vs 7d date)' do
    day = described_class.build(now: now, window_hours: 24)
    week = described_class.build(now: now, window_hours: 168)
    expect(day[:anchors].last[:en]).not_to eq(week[:anchors].last[:en])
  end

  it 'always emits a sparkline path even with nothing heard' do
    card = described_class.build(now: now, window_hours: 24)
    expect(card[:sparkline]).to include(:path, :fill, :w, :h)
    expect(card[:total]).to eq(0)
  end

  describe 'coverage (the heartbeat gate)' do
    let(:empty_buckets) { Array.new(24, 0) } # no detections either

    it 'treats every bucket as covered when NO heartbeats exist at all (cloud mirror)' do
      allow(Heartbeat).to receive(:exists?).and_return(false)
      cov = described_class.send(:coverage, now - 24.hours, 3600.0, empty_buckets)
      expect(cov).to all(be(true))
    end

    it 'marks a heartbeat-less, detection-less window as uncovered once heartbeats exist' do
      # This is the fix: a 12h view landing entirely inside a longer outage reads as "no
      # data" (all uncovered), the same as the 24h view around it — not a quiet resting line.
      allow(Heartbeat).to receive_messages(exists?: true, coverage: Array.new(24, false))
      cov = described_class.send(:coverage, now - 24.hours, 3600.0, empty_buckets)
      expect(cov).to all(be(false))
    end
  end
end
