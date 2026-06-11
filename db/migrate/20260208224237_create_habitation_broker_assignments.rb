class CreateHabitationBrokerAssignments < ActiveRecord::Migration[7.1]
  def change
    create_table :habitation_broker_assignments do |t|
      t.references :habitation, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :role
      t.string :commission_type
      t.decimal :commission_value, precision: 10, scale: 2
      t.text :observations

      t.timestamps
    end
  end
end
