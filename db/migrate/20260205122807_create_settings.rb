class CreateSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :settings do |t|
      t.string :key
      t.text :value
      t.string :description

      t.timestamps
    end
  end
end
