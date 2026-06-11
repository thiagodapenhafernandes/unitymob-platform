class AddIntakeSplitFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :intake_modalidade, :string
    add_column :habitations, :intake_group_uuid, :string

    add_index :habitations, :intake_modalidade
    add_index :habitations, :intake_group_uuid
  end
end
