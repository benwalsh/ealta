class CreateSpeciesInfos < ActiveRecord::Migration[8.1]
  # Cache of Wikipedia species descriptions (like the parent's detail panel).
  # Our own table — snake_case, unlike the birds.db-mirroring Detection.
  def change
    create_table :species_infos do |t|
      t.string :sci_name, null: false
      t.text :description
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :species_infos, :sci_name, unique: true
  end
end
