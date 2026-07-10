class CreateDetections < ActiveRecord::Migration[8.1]
  # Mirrors BirdNET-Pi's birds.db `detections` table column-for-column, so the
  # same model and queries work against this seeded dev DB and the real
  # read-only birds.db on the Pi. (birds.db has no primary key; we add one only
  # for dev ergonomics — the Pi read-model can set primary_key = false.)
  def change
    create_table :detections do |t| # rubocop:disable Rails/CreateTableWithTimestamps -- mirrors birds.db, which has none
      t.date    :Date
      t.time    :Time
      t.string  :Sci_Name, null: false
      t.string  :Com_Name, null: false
      t.float   :Confidence
      t.float   :Lat
      t.float   :Lon
      t.float   :Cutoff
      t.integer :Week
      t.float   :Sens
      t.float   :Overlap
      t.string  :File_Name
    end
    add_index :detections, :Sci_Name
    add_index :detections, %i[Date Time]
  end
end
