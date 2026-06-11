class AddCommercialInternalFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :captador_commission_percentage, :decimal, precision: 5, scale: 2
    add_column :habitations, :broker_commission_percentage, :decimal, precision: 5, scale: 2
    add_column :habitations, :salute_rental_management_flag, :boolean, default: false, null: false
    add_column :habitations, :key_location, :string
    add_column :habitations, :key_location_notes, :string

    add_index :habitations, :salute_rental_management_flag
    add_index :habitations, :key_location
    add_index :habitations, :aceita_permuta_flag
  end
end
