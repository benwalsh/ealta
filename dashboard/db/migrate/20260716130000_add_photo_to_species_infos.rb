class AddPhotoToSpeciesInfos < ActiveRecord::Migration[8.1]
  # A representative Wikimedia Commons photo for a species, cached like the song: the URL, its
  # attribution (artist · licence — CC images must be credited), and a fetched_photo_at sentinel so
  # a miss isn't re-fetched every send. Used only by the newsletter (the e-ink panel and the site
  # stay on the dithered illustrations). Additive and legal on SQLite and MySQL.
  def change
    add_column :species_infos, :photo_url, :string
    add_column :species_infos, :photo_credit, :string
    add_column :species_infos, :fetched_photo_at, :datetime
  end
end
