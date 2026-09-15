class AddFirstContactSlaMinutesToLeadSettings < ActiveRecord::Migration[7.1]
  def up
    add_column :lead_settings, :first_contact_sla_minutes, :integer
    execute <<~SQL.squish
      UPDATE lead_settings
         SET first_contact_sla_minutes = COALESCE(first_contact_sla_hours, 4) * 60
    SQL
    change_column_null :lead_settings, :first_contact_sla_minutes, false
    change_column_default :lead_settings, :first_contact_sla_minutes, 240
    add_check_constraint :lead_settings,
                         "first_contact_sla_minutes BETWEEN 1 AND 43200",
                         name: "lead_settings_first_contact_sla_minutes_range"
  end

  def down
    remove_check_constraint :lead_settings, name: "lead_settings_first_contact_sla_minutes_range"
    remove_column :lead_settings, :first_contact_sla_minutes
  end
end
