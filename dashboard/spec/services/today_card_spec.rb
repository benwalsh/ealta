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

  describe '.date_label' do
    it 'carries the year, with the Irish weekday in its proper Dé form' do
      label = described_class.date_label(Time.zone.local(2026, 7, 20, 12))
      expect(label[:en]).to eq('Monday, 20 July, 2026')
      expect(label[:ga]).to eq('Dé Luain, 20 Iúil, 2026')
    end

    it 'uses the inflected weekday, not a naive "Dé" prefix (Friday → Dé hAoine)' do
      expect(described_class.date_label(Time.zone.local(2026, 7, 24, 12))[:ga]).to start_with('Dé hAoine,')
    end
  end

  describe '.emphasised_bullets' do
    let(:facts) do
      { items: [{ sci_name: 'Tringa totanus', common_name: 'common redshank', irish_name: 'cosdeargán' }] }
    end

    it 'bolds the linked primary name and italicises the secondary in its parens' do
      bullet = described_class.emphasised_bullets(
        ['The **common redshank** (cosdeargán) was heard.'], facts, :en
      ).first
      expect(bullet).to include('<strong class="bird" data-sci="Tringa totanus">common redshank</strong>')
      expect(bullet).to include('<em class="bird-alt">cosdeargán</em>')
    end

    it 'trails a bullet with the inline citation for the bird it names' do
      cites = { 'Tringa totanus' => [{ label: 'Wikipedia', url: 'https://en.wikipedia.org/wiki/Common_redshank' }] }
      bullet = described_class.emphasised_bullets(
        ['The **common redshank** was heard.'], facts, :en, cites: cites
      ).first
      expect(bullet).to include('<span class="bullet-cites">').
        and include('href="https://en.wikipedia.org/wiki/Common_redshank"').
        and include('>Wikipedia</a>')
    end

    it 'leaves the bullet citation-free when no cites are supplied (the e-ink panel path)' do
      bullet = described_class.emphasised_bullets(['The **common redshank** was heard.'], facts, :en).first
      expect(bullet).not_to include('bullet-cites')
    end

    it 'injects the italic second name when the prose omits it, so naming stays consistent' do
      bullet = described_class.emphasised_bullets(['The **common redshank** was heard.'], facts, :en).first
      expect(bullet).to include('<strong class="bird" data-sci="Tringa totanus">common redshank</strong> ' \
                                '(<em class="bird-alt">cosdeargán</em>)')
    end

    it 'does not double up the second name the prose already carries' do
      bullet = described_class.emphasised_bullets(
        ['The **common redshank** (cosdeargán) was heard.'], facts, :en
      ).first
      expect(bullet.scan('cosdeargán').size).to eq(1)
    end

    it 'glosses a bird only once across the entry (first mention), not on every bullet' do
      bullets = described_class.emphasised_bullets(
        ['The **common redshank** arrived.', 'The **common redshank** called again.'], facts, :en
      )
      expect(bullets[0]).to include('<em class="bird-alt">cosdeargán</em>')
      expect(bullets[1]).not_to include('bird-alt')
    end
  end

  describe '.listening_seconds' do
    it 'is nil for the all-time span (a lifetime is not a listening duration)' do
      expect(described_class.listening_seconds(now: now, window_hours: 1_000_000)).to be_nil
    end

    it 'sums the covered span when no heartbeats exist at all (whole window listening)' do
      allow(Heartbeat).to receive(:exists?).and_return(false)
      expect(described_class.listening_seconds(now: now, window_hours: 24)).to eq(24 * 3600)
    end
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
