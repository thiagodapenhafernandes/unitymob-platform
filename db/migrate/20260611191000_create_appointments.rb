class CreateAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :appointments do |t|
      t.references :lead, null: true, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :habitation, null: true, foreign_key: true
      t.string :title, null: false
      t.string :kind, null: false, default: "visita"
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string :location
      t.string :status, null: false, default: "agendado"
      t.text :notes

      t.timestamps
    end

    add_index :appointments, [:admin_user_id, :starts_at]
    add_index :appointments, :starts_at
  end
end
