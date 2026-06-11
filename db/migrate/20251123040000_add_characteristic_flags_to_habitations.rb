class AddCharacteristicFlagsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :piscina_flag, :boolean, default: false
    add_column :habitations, :lavabo_flag, :boolean, default: false
    add_column :habitations, :varanda_gourmet_flag, :boolean, default: false
    
    add_index :habitations, :piscina_flag
    add_index :habitations, :lavabo_flag
  end
end
