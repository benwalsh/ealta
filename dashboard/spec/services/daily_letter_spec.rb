require 'rails_helper'

RSpec.describe DailyLetter do
  let(:date) { Date.yesterday }

  before { allow(Notifier).to receive(:enabled?).and_return(true) }

  def letter_subscriber(sci = 'Crex crex')
    create(:user).tap { |u| u.subscriptions.create!(alert_type: 'species', sci_name: sci, cadence: 'digest') }
  end

  def frozen_entry
    JournalEntry.create!(date: date, source: 'facts',
                         bullets: { en: ['A corncrake called at dusk.'], ga: ['Ghlaoigh traonach um thráthnóna.'] })
  end

  it 'mails the frozen Journal entry to a letter subscriber' do
    user = letter_subscriber
    entry = frozen_entry
    expect(Notifier).to receive(:deliver_letter).
      with(hash_including(user: user, date: date, entry: entry)).and_return(true)
    expect(described_class.deliver_all(date: date)).to eq(1)
  end

  it 'ignores immediate-cadence subscribers (already emailed live)' do
    create(:user).subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', cadence: 'immediate')
    frozen_entry
    expect(Notifier).not_to receive(:deliver_letter)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end

  it 'is idempotent — a second run the same day sends nothing' do
    letter_subscriber
    frozen_entry
    allow(Notifier).to receive(:deliver_letter).and_return(true)
    described_class.deliver_all(date: date)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end

  it 'leaves the day unmarked when the send fails, so the next sweep retries this reader' do
    user = letter_subscriber
    frozen_entry
    allow(Notifier).to receive(:deliver_letter).and_return(false) # a transient SES failure
    described_class.deliver_all(date: date)
    expect(user.reload.last_digest_on).to be_nil
  end

  it 'sends a frozen empty day (a quiet or offline day) — the reader still hears from the station' do
    user = letter_subscriber
    JournalEntry.create!(date: date, source: 'template',
                         bullets: { en: ['0 species'], ga: ['0 speiceas'] }, coverage: Array.new(24, true))
    expect(Notifier).to receive(:deliver_letter).with(hash_including(user: user, date: date)).and_return(true)
    expect(described_class.deliver_all(date: date)).to eq(1)
  end

  it "skips a thin day (unsaved template entry) but marks it done, so it won't rescan" do
    user = letter_subscriber
    # No detections and no lore → JournalEntry.for returns the UNSAVED template narration.
    allow(JournalEntry).to receive(:for).with(date).and_return(JournalEntry.new(date: date, source: 'template'))
    expect(Notifier).not_to receive(:deliver_letter)
    described_class.deliver_all(date: date)
    expect(user.reload.last_digest_on).to eq(date)
  end

  it 'reads the frozen hero, carrying the illustration slug when the station has that art' do
    JournalEntry.create!(date: date, source: 'facts', hero_sci_name: 'Passer domesticus',
                         bullets: { en: ['x'], ga: ['y'] })
    allow(BirdMask).to receive(:for).and_return(nil)
    allow(BirdMask).to receive(:for).with('passer-domesticus').and_return(instance_double(BirdMask))

    expect(described_class.hero_bird(date)).to include(sci: 'Passer domesticus', slug: 'passer-domesticus')
  end

  it 'still features the frozen hero when there is no art — no picture slug, for a later photo' do
    JournalEntry.create!(date: date, source: 'facts', hero_sci_name: 'Anser anser',
                         bullets: { en: ['x'], ga: ['y'] })
    allow(BirdMask).to receive(:for).and_return(nil)

    expect(described_class.hero_bird(date)).to include(sci: 'Anser anser', slug: nil)
  end

  it 'does nothing when sending is disabled (no ALERTS_FROM)' do
    allow(Notifier).to receive(:enabled?).and_return(false)
    letter_subscriber
    frozen_entry
    expect(described_class.deliver_all(date: date)).to eq(0)
  end
end
