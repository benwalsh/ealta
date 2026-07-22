FactoryBot.define do
  # A healthy wall: everything readable, nothing wrong. Specs override the one field they're
  # about, so the default has to be unambiguously fine — including the fields where null would
  # mean "unknown" rather than "good" (power, disk), since a warning that fires on unknowns
  # would make every test about something else fail for the wrong reason.
  factory :device_vital do
    station_key { DeviceVital::STATION_KEY }
    reported_at { Time.current }
    received_at { Time.current }
    git_sha { 'a1b2c3d' }
    git_dirty { false }
    boot_at { 3.days.ago }
    panel_ran_at { 10.minutes.ago }
    panel_pushed_at { 40.minutes.ago }
    panel_outcome { 'skipped' }
    services do
      { 'listener' => { 'state' => 'active', 'restarts' => 0 },
        'frame'    => { 'state' => 'active', 'restarts' => nil } }
    end
    litestream_at { 20.minutes.ago }
    disk_free_mb { 20_000 }
    disk_total_mb { 30_000 }
    cpu_temp_c { 44.2 }
    undervoltage_now { false }
    undervoltage_since_boot { false }
    mic_name { 'USBMIC1: USB Audio' }
  end
end
