class AddScheduleDetailsToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :properties_to_visit_count, :integer
    add_column :appointments, :invite_via_email, :boolean, null: false, default: false
    add_column :appointments, :invite_via_whatsapp, :boolean, null: false, default: false
    add_column :appointments, :invite_email_recipients, :text
  end
end
