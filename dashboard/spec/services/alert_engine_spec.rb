require 'rails_helper'

RSpec.describe AlertEngine do
  before { allow(Notifier).to receive(:deliver).and_return(true) }

  # Old enough for the first-ever / seasonal signals to have a baseline.
  def mature_age = DailyFacts::YOUNG_STATION_DAYS + 1

  # A DailyFacts item as the engine consumes it — only sci_name + flags matter here.
  def item(sci, *flags)
    { sci_name: sci, common_name: sci, irish_name: nil, call_count: 3, importance: 80, flags: flags }
  end

  # Stub the one facts engine so these specs test the alert mapping/gating, not the
  # (separately-specced) DailyFacts computation.
  def stub_facts(*items, age: mature_age)
    allow(DailyFacts).to receive(:for).and_return(items: items, station_age_days: age)
  end

  describe 'mapping DailyFacts flags to alert events' do
    it 'fires a rarity event from a rare_local flag' do
      stub_facts(item('Crex crex', 'rare_local'))
      expect { described_class.scan }.
        to change { Event.where(event_type: 'rarity', sci_name: 'Crex crex').count }.by(1)
    end

    it 'fires a first_ever event from all_time_first on a mature station' do
      stub_facts(item('Crex crex', 'all_time_first'))
      expect { described_class.scan }.to change { Event.where(event_type: 'first_ever').count }.by(1)
    end

    it 'fires a seasonal event from year_first on a mature station' do
      stub_facts(item('Cuculus canorus', 'year_first'))
      expect { described_class.scan }.
        to change { Event.where(event_type: 'seasonal', sci_name: 'Cuculus canorus').count }.by(1)
    end

    it 'ignores texture flags (most_common / unusual_volume_low / routine)' do
      stub_facts(item('Passer domesticus', 'most_common', 'unusual_volume_low', 'routine'))
      expect { described_class.scan }.not_to(change(Event, :count))
    end
  end

  describe 'young-station gating' do
    it 'holds first_ever and seasonal while the station is young' do
      stub_facts(item('Crex crex', 'all_time_first', 'year_first'), age: 30)
      expect { described_class.scan }.
        not_to(change { Event.where(event_type: %w[first_ever seasonal]).count })
    end

    it 'still fires rarity on a young station (rarity self-gates on its own baseline)' do
      stub_facts(item('Crex crex', 'rare_local'), age: 30)
      expect { described_class.scan }.to change { Event.where(event_type: 'rarity').count }.by(1)
    end
  end

  describe 'follows' do
    it 'fires a species event when someone follows a bird heard today — even young' do
      create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      stub_facts(item('Crex crex', 'routine'), age: 5)
      expect { described_class.scan }.
        to change { Event.where(event_type: 'species', sci_name: 'Crex crex').count }.by(1)
    end

    it 'does not fire a species event with no subscribers' do
      stub_facts(item('Crex crex', 'routine'))
      expect { described_class.scan }.not_to(change { Event.where(event_type: 'species').count })
    end
  end

  describe 'delivery' do
    it 'is fire-once — a second scan records nothing new' do
      create(:subscription, sci_name: 'Crex crex')
      stub_facts(item('Crex crex', 'routine'))
      described_class.scan
      expect { described_class.scan }.not_to(change(Event, :count))
    end

    it 'delivers a pending event to the matching subscriber and marks it notified' do
      sub = create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      stub_facts(item('Crex crex', 'routine'))
      expect(Notifier).to receive(:deliver).
        with(event: an_instance_of(Event), subscription: sub).and_return(true)
      described_class.scan
      expect(Event.find_by(event_type: 'species').notified_at).to be_present
    end

    it 'leaves an event unsent when delivery fails, so the next tick retries' do
      create(:subscription, sci_name: 'Crex crex')
      stub_facts(item('Crex crex', 'routine'))
      allow(Notifier).to receive(:deliver).and_return(false)
      described_class.scan
      expect(Event.find_by(event_type: 'species').notified_at).to be_nil
    end
  end

  describe 'cadence gating (the immediate path)' do
    it 'does not email digest-cadence subscribers now — but still records the event for the digest' do
      create(:subscription, alert_type: 'species', sci_name: 'Crex crex', cadence: 'digest')
      stub_facts(item('Crex crex', 'routine'))
      expect(Notifier).not_to receive(:deliver)
      described_class.scan
      expect(Event.where(event_type: 'species', sci_name: 'Crex crex')).to exist
    end

    it 'never emails off-cadence subscribers' do
      create(:subscription, alert_type: 'species', sci_name: 'Crex crex', cadence: 'off')
      stub_facts(item('Crex crex', 'routine'))
      expect(Notifier).not_to receive(:deliver)
      described_class.scan
    end
  end
end
