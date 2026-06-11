class AddVistaSourceKeyToHabitationBrokerAssignments < ActiveRecord::Migration[7.1]
  def change
    add_column :habitation_broker_assignments, :vista_source_key, :string
    add_index :habitation_broker_assignments,
              [:vista_import_batch_id, :vista_source_key],
              unique: true,
              where: "vista_source_key IS NOT NULL",
              name: "idx_hba_vista_batch_source_key"
  end
end
