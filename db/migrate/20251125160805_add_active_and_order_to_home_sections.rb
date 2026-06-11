class AddActiveAndOrderToHomeSections < ActiveRecord::Migration[7.1]
  def change
    # active column already exists, only add order_position
    add_column :home_sections, :order_position, :integer, default: 0
  end
end
