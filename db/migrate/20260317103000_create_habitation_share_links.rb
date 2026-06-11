class CreateHabitationShareLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :habitation_share_links do |t|
      t.references :habitation, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_clicked_at
      t.integer :clicks_count, null: false, default: 0

      t.timestamps
    end

    add_index :habitation_share_links, :token, unique: true
    add_index :habitation_share_links, [:habitation_id, :admin_user_id, :expires_at], name: 'idx_hab_share_links_hab_admin_exp'
  end
end
