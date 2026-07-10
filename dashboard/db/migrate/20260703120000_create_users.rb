class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.string :name
      t.string :avatar_url
      t.timestamps
    end
    add_index :users, %i[provider uid], unique: true
    add_index :users, :email
  end
end
