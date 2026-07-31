class AddBrokerIntakeSnapshotToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :broker_intake_snapshot, :jsonb, default: {}, null: false
  end
end
