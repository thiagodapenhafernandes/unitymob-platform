class ChangeCaracteristicaUnicaToTextArrayInHabitations < ActiveRecord::Migration[7.1]
  def change
    change_column :habitations, :caracteristica_unica, "text[] USING (string_to_array(caracteristica_unica, ','))"
    change_column_default :habitations, :caracteristica_unica, []
  end
end
