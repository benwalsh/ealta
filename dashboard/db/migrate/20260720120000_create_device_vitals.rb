# "How is the box?" — the current state of the physical station, pushed up by birdnet/vitals.py
# on the same fifteen-minute timer as the detections.
#
# Deliberately NOT more columns on heartbeats. A heartbeat is an append-only event stream
# answering "was the listener alive at this instant", kept for two days and read as a series;
# this is a single mutable row answering "what is the machine like right now", with no history
# worth keeping — last week's SD-card free space tells nobody anything. Folding the two together
# would mean either writing a hundred vitals columns per tick or teaching the heartbeat reader
# to skip mostly-null rows, and both are worse than a second small table.
#
# Hence one row, upserted on station_key. The cloud is single-tenant (one wall, one station), so
# the key is a constant rather than a real tenancy — it exists to give upsert_all a conflict
# target, which both engines need and neither can infer from "there is only ever one row".
#
# Every column is nullable and means "unknown" when null, because collection on the device is
# best-effort by design: there is no vcgencmd on a Mac and no systemctl either, and a station
# that can't read its own temperature must be able to say so rather than claim zero. That also
# keeps the migration legal on both engines — no literal default on the JSON services column
# (MySQL 1101 forbids it); its {} default lives on the model instead.
#
# The booleans are three-state on purpose, which is why Rails/ThreeStateBooleanColumn is
# disabled below rather than obeyed. The cop is right about ordinary flags — a NOT NULL with a
# default is what you want when false is a real answer. Here it isn't: "the power supply is
# fine" and "this machine has no vcgencmd, so nobody asked" are different claims, and a NOT
# NULL false column can only make the second look like the first. On a wall-mounted box that is
# the difference between a panel that says nothing and a panel that says something untrue.
class CreateDeviceVitals < ActiveRecord::Migration[8.1]
  def change
    # rubocop:disable Rails/ThreeStateBooleanColumn
    create_table :device_vitals do |t|
      t.string :station_key, null: false

      # Two clocks, on purpose. reported_at is the device's own reading; received_at is ours.
      # Staleness is measured against received_at alone — a Pi whose clock has drifted (an NTP
      # failure is itself a symptom worth seeing) must not be able to report itself as current.
      t.datetime :reported_at
      t.datetime :received_at, null: false

      # What is actually deployed. A dirty tree means the running code is no longer any commit.
      t.string :git_sha
      t.boolean :git_dirty

      t.datetime :boot_at

      # The panel: when pixels last reached the glass, when the shooter last ran at all, and
      # what that run did. A skip is healthy; a skip is also what a dead timer looks like if
      # you only record the push, which is why all three are here.
      t.datetime :panel_ran_at
      t.datetime :panel_pushed_at
      t.string :panel_outcome

      # {"listener" => {"state" => "active", "restarts" => 3}, …}. JSON rather than a column
      # per unit so adding a service to watch is a device-side change, not a migration.
      t.json :services

      t.datetime :litestream_at
      t.string :litestream_error

      t.integer :disk_free_mb
      t.integer :disk_total_mb
      t.float :cpu_temp_c

      # Undervoltage, decoded on the device into two plain booleans. Since-boot is the one that
      # matters: it outlives the brownout, and brownouts are a known cause of the SD corruption
      # the Litestream restore path exists to undo.
      t.boolean :undervoltage_now
      t.boolean :undervoltage_since_boot

      t.string :mic_name

      t.timestamps
    end
    # rubocop:enable Rails/ThreeStateBooleanColumn
    add_index :device_vitals, :station_key, unique: true
  end
end
