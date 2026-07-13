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

  it "skips a thin day (unsaved template entry) but marks it done, so it won't rescan" do
    user = letter_subscriber
    # No detections and no lore → JournalEntry.for returns the UNSAVED template narration.
    allow(JournalEntry).to receive(:for).with(date).and_return(JournalEntry.new(date: date, source: 'template'))
    expect(Notifier).not_to receive(:deliver_letter)
    described_class.deliver_all(date: date)
    expect(user.reload.last_digest_on).to eq(date)
  end

  it 'picks the most notable bird WITH art as the hero' do
    allow(DailyFacts).to receive(:for).and_return(
      { items: [
        { sci_name: 'Anser anser', common_name: 'Greylag Goose', irish_name: 'Gé ghlas', importance: 90 },
        { sci_name: 'Passer domesticus', common_name: 'House Sparrow', irish_name: 'Gealbhan binne', importance: 10 }
      ] }
    )
    # The goose has no art; the sparrow does — the hero is the best bird we can PICTURE.
    allow(BirdMask).to receive(:for).and_return(nil)
    allow(BirdMask).to receive(:for).with('passer-domesticus').and_return(instance_double(BirdMask))
    hero = described_class.hero_bird(date)
    expect(hero).to include(sci: 'Passer domesticus', slug: 'passer-domesticus', en: 'House Sparrow')
  end

  it 'does nothing when sending is disabled (no ALERTS_FROM)' do
    allow(Notifier).to receive(:enabled?).and_return(false)
    letter_subscriber
    frozen_entry
    expect(described_class.deliver_all(date: date)).to eq(0)
  end
end
