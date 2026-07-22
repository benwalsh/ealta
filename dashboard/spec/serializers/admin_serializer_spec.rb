require 'rails_helper'

RSpec.describe AdminSerializer do
  subject(:payload) { described_class.health(AdminHealth.snapshot) }

  describe 'the device block' do
    it 'reports nothing where the station has never checked in' do
      expect(payload[:device]).to eq(reporting: 'none')
    end

    it 'crosses the readings with times as ISO strings' do
      create(:device_vital, git_sha: 'a1b2c3d', cpu_temp_c: 44.2, mic_name: 'USBMIC1')
      device = payload[:device]

      expect(device[:reporting]).to eq('fresh')
      expect(device[:version]).to eq(sha: 'a1b2c3d', dirty: false)
      expect(device[:cpu_temp_c]).to eq(44.2)
      expect(device[:mic_name]).to eq('USBMIC1')
      expect(device[:received_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(device[:panel][:pushed_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(device[:warnings]).to be_empty
    end

    # The point of shipping staleness alongside the readings: a wall that went dark an hour ago
    # must not be able to look like one reporting healthy values. The figures still cross — they
    # are the last thing known — but the payload says out loud that they are old.
    it 'marks the whole report stale, and says so in words, once the pushes stop' do
      create(:device_vital, received_at: 3.hours.ago, cpu_temp_c: 44.2)
      device = payload[:device]

      expect(device[:reporting]).to eq('stale')
      expect(device[:cpu_temp_c]).to eq(44.2)
      expect(device[:warnings].first).to include('last reported', 'last known state')
    end

    # Undervoltage is the field most likely to be misread as trivia, so it crosses as a sentence
    # naming the consequence rather than as a bit — the device decodes the throttle word itself.
    it 'warns about undervoltage in plain words, never as a code' do
      create(:device_vital, undervoltage_since_boot: true)
      warning = payload[:device][:warnings].find { |w| w.include?('power supply') }

      expect(warning).to include('sagged at least once', 'corrupt the SD card')
      expect(payload[:device][:warnings].join).not_to match(/0x/i)
    end

    # The highest-value field: e-ink holds its last image forever, so a frozen panel is
    # indistinguishable from a working one unless something says how old the pixels are.
    it 'warns when the panel has not refreshed in a very long time' do
      create(:device_vital, panel_pushed_at: 3.days.ago, panel_ran_at: 5.minutes.ago)
      expect(payload[:device][:warnings].join).to include('The panel has not refreshed')
    end

    # A skip is the healthy case — the shooter deliberately spares the panel a refresh when the
    # station screen is unchanged — so a recent run that skipped must not read as a fault.
    it 'does not warn when the last run merely skipped an unchanged screen' do
      create(:device_vital, panel_outcome: 'skipped', panel_ran_at: 5.minutes.ago,
                            panel_pushed_at: 2.hours.ago)
      expect(payload[:device][:warnings]).to be_empty
    end

    # A crash loop is invisible to a state check: "active" on the two-hundredth start reads
    # exactly like "active" on the first, which is why restart counts travel with the state.
    it 'surfaces stopped services and crash loops separately' do
      create(:device_vital, services: { 'listener' => { 'state' => 'active', 'restarts' => 240 },
                                        'web'      => { 'state' => 'failed', 'restarts' => 0 } })
      warnings = payload[:device][:warnings].join

      expect(warnings).to include('Not running: web')
      expect(warnings).to include('Restarting repeatedly: listener')
      expect(payload[:device][:services]['listener']['restarts']).to eq(240)
    end

    # Best-effort collection means most fields are null on anything that isn't a Pi. Null is
    # "unknown", and warning about unknowns would train everyone to ignore the warning list.
    it 'stays silent about fields the device could not read' do
      create(:device_vital, undervoltage_now: nil, undervoltage_since_boot: nil,
                            disk_free_mb: nil, disk_total_mb: nil, cpu_temp_c: nil, services: nil)
      device = payload[:device]

      expect(device[:warnings]).to be_empty
      expect(device[:power]).to eq(now: nil, since_boot: nil)
      expect(device[:services]).to be_nil
    end
  end
end
