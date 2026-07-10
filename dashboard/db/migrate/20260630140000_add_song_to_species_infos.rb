class AddSongToSpeciesInfos < ActiveRecord::Migration[8.1]
  # A playable song/call sample (a Wikimedia Commons audio URL) for the inline
  # player in the detail card. fetched_song_at remembers a *missing* recording
  # (some species have none) so we don't re-hit Wikipedia on every modal open.
  def change
    add_column :species_infos, :song_url, :string
    add_column :species_infos, :fetched_song_at, :datetime
  end
end
