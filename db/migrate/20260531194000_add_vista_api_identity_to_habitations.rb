class AddVistaApiIdentityToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :vista_codigo, :string
    add_column :habitations, :vista_imo_codigo, :string
    add_column :habitations, :vista_imo_placa, :string
    add_column :habitations, :vista_referencia_externa, :string

    add_index :habitations, :vista_codigo
    add_index :habitations, :vista_imo_codigo
    add_index :habitations, :vista_imo_placa
    add_index :habitations, :vista_referencia_externa
  end
end
