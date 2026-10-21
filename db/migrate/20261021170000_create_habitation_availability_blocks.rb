class CreateHabitationAvailabilityBlocks < ActiveRecord::Migration[7.1]
  def change
    create_table :habitation_availability_blocks do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :habitation, null: false, foreign_key: true
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.timestamps
    end
    add_index :habitation_availability_blocks, [:habitation_id, :starts_on, :ends_on], name: "index_habitation_availability_periods"
    add_check_constraint :habitation_availability_blocks, "ends_on >= starts_on", name: "habitation_availability_valid_period"
  end
end
