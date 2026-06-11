class AddHomeCorporateFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :home_corporate_flag, :boolean, default: false, null: false
    add_column :habitations, :home_corporate_position, :integer

    add_index :habitations, :home_corporate_flag
    add_index :habitations, [:home_corporate_flag, :home_corporate_position], name: "idx_habitations_home_corporate_order"
  end
end
