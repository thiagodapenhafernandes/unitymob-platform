class CreateLeadLabelings < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_labelings do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :lead_label, null: false, foreign_key: true
      t.timestamps
    end

    add_index :lead_labelings, [:lead_id, :lead_label_id], unique: true
  end
end
