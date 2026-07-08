class CreateHabitationPhotoShares < ActiveRecord::Migration[7.1]
  def change
    create_table :habitation_photo_shares do |t|
      t.references :habitation, null: false, foreign_key: true
      t.references :admin_user, null: true, foreign_key: true
      t.string :token, null: false
      t.jsonb :photo_ids, null: false, default: []
      t.datetime :expires_at
      t.datetime :last_viewed_at
      t.integer :views_count, null: false, default: 0

      t.timestamps
    end

    add_index :habitation_photo_shares, :token, unique: true
  end
end
