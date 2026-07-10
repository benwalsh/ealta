class AddIrishDescriptionToSpeciesInfos < ActiveRecord::Migration[8.1]
  # Irish-language Wikipedia prose for the bilingual toggle. fetched_ga_at lets us
  # remember a *missing* Irish article (many birds lack one) so we don't re-hit
  # ga.wikipedia on every modal open.
  def change
    add_column :species_infos, :description_ga, :text
    add_column :species_infos, :fetched_ga_at, :datetime
  end
end
