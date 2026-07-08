class AddQuadraToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :quadra, :string
  end
end
