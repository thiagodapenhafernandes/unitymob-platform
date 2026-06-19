class CreateHabitationExports < ActiveRecord::Migration[7.1]
  def change
    create_table :habitation_exports do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :progress, null: false, default: 0
      t.string :filename
      t.integer :record_count, null: false, default: 0
      t.jsonb :fields, null: false, default: []
      t.jsonb :source_ids, null: false, default: []
      t.string :col_sep, null: false, default: ";"
      t.text :error_message
      t.timestamps
    end
    add_index :habitation_exports, [:admin_user_id, :created_at]
  end
end
