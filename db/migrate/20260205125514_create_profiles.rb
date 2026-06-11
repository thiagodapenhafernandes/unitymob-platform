class CreateProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :profiles do |t|
      t.string :name
      t.jsonb :permissions
      t.boolean :active

      t.timestamps
    end
  end
end
