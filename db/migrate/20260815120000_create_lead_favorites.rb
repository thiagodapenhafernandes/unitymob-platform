class CreateLeadFavorites < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_favorites do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true

      t.timestamps
    end

    add_index :lead_favorites, [:admin_user_id, :lead_id], unique: true
    add_index :lead_favorites, [:tenant_id, :admin_user_id]
  end
end
