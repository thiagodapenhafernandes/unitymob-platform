class AddRoomCountsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :salas_qtd, :integer
    add_column :habitations, :varandas_qtd, :integer
  end
end
