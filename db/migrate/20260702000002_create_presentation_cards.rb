class CreatePresentationCards < ActiveRecord::Migration[7.1]
  def change
    create_table :presentation_cards do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :label, null: false
      t.text :greeting, null: false
      t.boolean :use_photo, null: false, default: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :presentation_cards, [:admin_user_id, :position]
  end
end
