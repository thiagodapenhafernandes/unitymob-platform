class AddIntakeStepToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :intake_step, :string, default: "intro", null: false
    add_index :habitations, :intake_step
  end
end
