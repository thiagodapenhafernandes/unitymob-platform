class CreateLeadLabels < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_labels do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "gray"
      t.integer :position, null: false
      t.timestamps
    end

    add_index :lead_labels, [:admin_user_id, :name], unique: true
    add_index :lead_labels, [:admin_user_id, :position]
  end
end
