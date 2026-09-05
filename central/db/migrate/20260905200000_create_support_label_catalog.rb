class CreateSupportLabelCatalog < ActiveRecord::Migration[7.1]
  def up
    create_table :support_labels do |t|
      t.string :name, null: false, limit: 40
      t.string :color, null: false, default: '#64748b'
      t.string :description, limit: 160
      t.timestamps
    end
    add_index :support_labels, 'lower(name)', unique: true
    execute <<~SQL
      INSERT INTO support_labels (name, color, created_at, updated_at)
      SELECT DISTINCT ON (lower(trim(value))) left(trim(value),40), '#64748b', NOW(), NOW()
      FROM support_tickets, unnest(string_to_array(labels, ',')) value
      WHERE trim(value) <> '' ON CONFLICT DO NOTHING
    SQL
  end
  def down
    drop_table :support_labels
  end
end
