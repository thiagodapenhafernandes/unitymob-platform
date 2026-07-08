class CreateLeadPropertyInterests < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_property_interests do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :habitation, null: false, foreign_key: true
      t.timestamps
    end

    add_index :lead_property_interests, [:lead_id, :habitation_id], unique: true
  end
end
